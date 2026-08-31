import Foundation
import Testing

@testable import Ozymandias

struct APIClientTests {
  private let baseURL = URL(string: "http://localhost:8787")!

  @Test func validatesHealthyServer() async throws {
    let session = MockHTTPSession { request in
      #expect(request.url?.path == "/healthz")
      return Self.response(
        for: request, status: 200, json: #"{"status":"ok","time":"2026-08-28T12:00:00Z"}"#)
    }
    let health = try await APIClient(baseURL: baseURL, session: session).health()
    #expect(health.status == "ok")
  }

  @Test func rejectsUnexpectedHealthPayload() async {
    let session = MockHTTPSession { request in
      Self.response(for: request, status: 200, json: #"{"status":"starting","time":"now"}"#)
    }
    await #expect(throws: APIClientError.self) {
      try await APIClient(baseURL: baseURL, session: session).health()
    }
  }

  @Test func loginSendsNativeClientContract() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      return Self.response(
        for: request,
        status: 200,
        json:
          #"{"username":"ana","must_change_password":false,"is_admin":true,"token":"secret","expira_em":"2099-08-28T12:00:00Z"}"#
      )
    }
    let user = try await APIClient(baseURL: baseURL, session: session)
      .login(username: "ana", password: "password", remember: true)
    #expect(user.username == "ana")
    let request = await recorder.request
    #expect(request?.httpMethod == "POST")
    let body = try #require(request?.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["token_na_resposta"] as? Bool == true)
    #expect(json["remember"] as? Bool == true)
  }

  @Test func preservesServerErrorMessageAndStatus() async {
    let session = MockHTTPSession { request in
      Self.response(for: request, status: 401, json: #"{"error":"usuário ou senha incorretos"}"#)
    }
    do {
      _ = try await APIClient(baseURL: baseURL, session: session)
        .login(username: "x", password: "y", remember: false)
      Issue.record("O login deveria falhar")
    } catch let error as APIClientError {
      #expect(error.statusCode == 401)
      #expect(error.localizedDescription == "usuário ou senha incorretos")
    } catch {
      Issue.record("Erro inesperado: \(error)")
    }
  }

  @Test func approvesTVUsingBearerAndHumanCode() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      return Self.response(
        for: request, status: 200,
        json: #"{"ok":true,"device_name":"Fire TV da sala"}"#)
    }
    let response = try await APIClient(baseURL: baseURL, session: session)
      .approveDevice(userCode: "ABCD-EFGH", token: "session-token")
    #expect(response.deviceName == "Fire TV da sala")
    let request = await recorder.request
    #expect(request?.url?.path == "/api/auth/device/approve")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    let body = try #require(request?.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["user_code"] == "ABCD-EFGH")
  }

  @Test func extractsTVCodeFromQRCodeURL() {
    #expect(
      TVPairingCode.extract(from: "http://ozymandias.local:8787/conectar?codigo=ABCD-EFGH")
        == "ABCD-EFGH")
    #expect(TVPairingCode.extract(from: "abcdefgh") == "ABCD-EFGH")
    #expect(TVPairingCode.extract(from: "codigo-invalido") == nil)
  }

  @Test func mapsTimeoutToFriendlyMessage() async {
    let session = MockHTTPSession { _ in throw URLError(.timedOut) }
    await #expect(throws: APIClientError.self) {
      try await APIClient(baseURL: baseURL, session: session).health()
    }
  }

  @Test func retriesTransientReadAfterNetworkTransition() async throws {
    let attempts = AttemptCounter()
    let session = MockHTTPSession { request in
      if await attempts.increment() == 1 {
        throw URLError(.networkConnectionLost)
      }
      return Self.response(
        for: request, status: 200,
        json: #"{"status":"ok","time":"2026-08-28T12:00:00Z"}"#)
    }

    let health = try await APIClient(baseURL: baseURL, session: session).health()

    #expect(health.status == "ok")
    #expect(await attempts.value == 2)
  }

  @Test func doesNotRetryLoginAfterTransientFailure() async {
    let attempts = AttemptCounter()
    let session = MockHTTPSession { _ in
      _ = await attempts.increment()
      throw URLError(.networkConnectionLost)
    }

    await #expect(throws: APIClientError.self) {
      try await APIClient(baseURL: baseURL, session: session)
        .login(username: "ana", password: "password", remember: true)
    }
    #expect(await attempts.value == 1)
  }

  @Test func loadsAuthenticatedHomeContract() async throws {
    let session = MockHTTPSession { request in
      #expect(request.url?.path == "/api/home")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
      return Self.response(
        for: request,
        status: 200,
        json:
          #"{"hero":{"id":7,"library_id":2,"kind":"movie","name":"Duna","year":2024,"files":1,"meta_state":"ready"},"continue":[],"rows":[]}"#
      )
    }

    let home = try await APIClient(baseURL: baseURL, session: session).home(token: "token")

    #expect(home.hero?.name == "Duna")
    #expect(home.continueItems.isEmpty)
  }

  @Test func loadsCatalogAndLibraries() async throws {
    let session = MockHTTPSession { request in
      if request.url?.path == "/api/libraries" {
        return Self.response(
          for: request, status: 200,
          json: #"[{"id":2,"name":"Filmes","kind":"movie","enabled":true}]"#)
      }
      return Self.response(
        for: request, status: 200,
        json:
          #"{"items":[{"id":7,"library_id":2,"kind":"movie","name":"Duna","files":1,"meta_state":"ready"}],"total":1,"offset":0,"limit":60}"#
      )
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let libraries = try await client.libraries(token: "token")
    let titles = try await client.titles(token: "token")

    #expect(libraries.first?.name == "Filmes")
    #expect(titles.items.first?.name == "Duna")
  }

  @Test func loadsTitleDetailAndChangesFavorite() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      if request.url?.path == "/api/titles/7" {
        return Self.response(
          for: request, status: 200,
          json:
            #"{"id":7,"library_id":2,"kind":"movie","name":"Duna","year":2024,"overview":"Arrakis.","meta_state":"matched","library":"Filmes","favorite":false,"files":[{"id":70,"rel_path":"Duna.mkv","name":"Duna","ext":"mkv","media_type":"video","size":1000,"duration":9000}]}"#
        )
      }
      return Self.response(for: request, status: 200, json: #"{"favorite":true}"#)
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let detail = try await client.title(id: 7, token: "token")
    #expect(detail.files.first?.mediaType == .video)
    _ = try await client.setFavorite(titleID: 7, favorite: true, token: "token")

    let request = await recorder.request
    #expect(request?.url?.path == "/api/favorites/7")
    #expect(request?.httpMethod == "POST")
  }

  @Test func negotiatesNativePlaybackAndRequestsMediaToken() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      if request.url?.path == "/api/auth/media-token" {
        return Self.response(
          for: request, status: 200,
          json:
            #"{"token":"media","expira_em":"2099-08-28T12:00:00Z","valido_por":7200,"param":"t"}"#
        )
      }
      return Self.response(
        for: request, status: 200,
        json:
          #"{"modo":"direct","motivo":"compatível","url":"/stream/70","url_direta":"/stream/70","ffmpeg":true,"transcodificacao_ativa":true}"#
      )
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let mediaToken = try await client.mediaToken(token: "session")
    let plan = try await client.playback(fileID: 70, token: "session")

    #expect(mediaToken.parameter == "t")
    #expect(plan.mode == .direct)
    let recorded = await requests.requests
    let playbackURL = try #require(recorded.last?.url)
    let components = try #require(URLComponents(url: playbackURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      })
    #expect(query["vid"] == "h264,hevc")
    #expect(query["aud"]?.contains("aac") == true)
    #expect(query["cont"]?.contains("mp4") == true)
  }

  @Test func savesPlaybackProgressWithBearer() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
      return (Data(), response)
    }

    try await APIClient(baseURL: baseURL, session: session).saveProgress(
      fileID: 70, position: 120, duration: 9000, token: "session")

    let request = await recorder.request
    #expect(request?.httpMethod == "PUT")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer session")
    let body = try #require(request?.httpBody)
    let progress = try JSONDecoder().decode(ProgressRequest.self, from: body)
    #expect(progress.position == 120)
    #expect(progress.duration == 9000)
  }

  @Test func loadsTracksNextEpisodeAndKeepsSelectedAudioInPlan() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      switch request.url?.path {
      case "/api/files/70/faixas":
        return Self.response(
          for: request, status: 200,
          json:
            #"{"audio":[{"idx":3,"codec":"aac","lang":"por","rotulo":"Português · 5.1","padrao":false}],"legendas":[{"idx":4,"codec":"subrip","lang":"eng","rotulo":"Inglês","url":"/api/files/70/legenda/4.vtt"}]}"#
        )
      case "/api/files/70/next":
        return Self.response(for: request, status: 200, json: #"{"next":71}"#)
      default:
        return Self.response(
          for: request, status: 200,
          json:
            #"{"modo":"remux","motivo":"troca de áudio","url":"/preparado/70?audio=3","url_direta":"/stream/70","ffmpeg":true,"transcodificacao_ativa":true}"#
        )
      }
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let tracks = try await client.tracks(fileID: 70, token: "session")
    let next = try await client.nextEpisode(fileID: 70, token: "session")
    _ = try await client.playback(fileID: 70, audioTrack: 3, token: "session")

    #expect(tracks.audio.first?.label == "Português · 5.1")
    #expect(tracks.subtitles.first?.url == "/api/files/70/legenda/4.vtt")
    #expect(next.next == 71)
    let recorded = await requests.requests
    let playback = try #require(recorded.last?.url)
    let components = try #require(URLComponents(url: playback, resolvingAgainstBaseURL: false))
    #expect(components.queryItems?.first(where: { $0.name == "audio" })?.value == "3")
  }

  @Test func parsesWebVTTWithHoursStylesAndCommaMilliseconds() throws {
    let source = """
      WEBVTT

      1
      00:00:01.500 --> 00:00:03.000 align:center
      <b>Primeira fala</b>

      00:04,250 --> 00:06,000
      Segunda &amp; última
      """

    let cues = WebVTTParser.parse(source)

    #expect(cues.count == 2)
    #expect(cues[0].start == 1.5)
    #expect(cues[0].text == "Primeira fala")
    #expect(cues[1].contains(5))
    #expect(cues[1].text == "Segunda & última")
  }

  @Test func sendsServerSideCatalogSearchFiltersAndSort() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      return Self.response(
        for: request, status: 200,
        json: #"{"items":[],"total":0,"offset":0,"limit":30}"#)
    }

    _ = try await APIClient(baseURL: baseURL, session: session).titles(
      query: CatalogQuery(
        libraryID: 8, kind: .tv, text: "Fundação & Império", sort: .year, limit: 30),
      token: "session"
    )

    let url = try #require(await recorder.request?.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      })
    #expect(query["library"] == "8")
    #expect(query["kind"] == "tv")
    #expect(query["q"] == "Fundação & Império")
    #expect(query["sort"] == "year")
    #expect(query["limit"] == "30")
  }

  @Test func managesCollectionsAndTitleMembership() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      switch (request.httpMethod, request.url?.path) {
      case ("GET", "/api/colecoes"):
        return Self.response(
          for: request, status: 200,
          json:
            #"[{"id":4,"nome":"Fim de semana","itens":1,"criada_em":10,"atualizada_em":20}]"#
        )
      case ("POST", "/api/colecoes"):
        return Self.response(
          for: request, status: 201,
          json:
            #"{"id":5,"nome":"Favoritos da casa","itens":0,"criada_em":30,"atualizada_em":30}"#
        )
      case ("GET", "/api/titles/7/colecoes"):
        return Self.response(for: request, status: 200, json: #"{"colecoes":[4]}"#)
      default:
        return Self.response(for: request, status: 200, json: #"{"ok":true}"#)
      }
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let collections = try await client.collections(token: "session")
    let created = try await client.createCollection(name: "Favoritos da casa", token: "session")
    let selected = try await client.collectionIDs(titleID: 7, token: "session")
    try await client.setCollectionMembership(
      collectionID: 4, titleID: 7, included: false, token: "session")

    #expect(collections.first?.name == "Fim de semana")
    #expect(created.id == 5)
    #expect(selected == [4])
    let recorded = await requests.requests
    let membership = try #require(recorded.last)
    #expect(membership.httpMethod == "DELETE")
    #expect(membership.url?.path == "/api/colecoes/4/itens/7")
  }

  @Test func loadsScanStatusAndStartsMaintenance() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      if request.url?.path == "/api/scan/status" {
        return Self.response(
          for: request, status: 200,
          json:
            #"{"running":true,"stage":"arquivos","library":"Filmes","current":3,"total":10,"file":"filme.mp4"}"#
        )
      }
      return Self.response(for: request, status: 202, json: #"{"started":true}"#)
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let status = try await client.scanStatus(token: "session")
    let scan = try await client.startScan(token: "session")
    let metadata = try await client.refreshMetadata(all: true, token: "session")

    #expect(status.running)
    #expect(status.current == 3)
    #expect(scan.started)
    #expect(metadata.started)
    let recorded = await requests.requests
    #expect(recorded[1].httpMethod == "POST")
    #expect(recorded[1].url?.path == "/api/scan")
    #expect(recorded[2].url?.path == "/api/metadata")
    #expect(recorded[2].url?.query == "all=1")
  }

  @Test func loadsAdminMetrics() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      return Self.response(
        for: request, status: 200,
        json:
          #"{"uptime_segundos":7200,"modo":"local","processo":{"cpu_percent":2.5,"cpu_nucleos":0.1,"heap_bytes":10485760,"rss_pico_bytes":20971520,"goroutines":12,"nucleos":8},"disco_livre_bytes":500000000000,"disco_total_bytes":1000000000000,"disco_reserva_bytes":10000000000,"cache_usado_bytes":100000000,"cache_limite_bytes":1000000000,"trafego":{"total":20,"erros":1,"taxa_erro":0.05,"descartadas":2,"rotas":[{"rota":"GET /api/home","total":12,"erros_4xx":1,"erros_5xx":0,"taxa_erro":0.083,"media_ms":8.5,"max_ms":25,"p50_ms":7,"p95_ms":18}]}}"#
      )
    }

    let metrics = try await APIClient(baseURL: baseURL, session: session).metrics(token: "session")

    #expect(metrics.freeDiskBytes == 500_000_000_000)
    #expect(metrics.process.cpuPercent == 2.5)
    #expect(metrics.traffic.routes.first?.p95MS == 18)
    #expect(await recorder.request?.value(forHTTPHeaderField: "Authorization") == "Bearer session")
  }

  @Test func loadsAndUpdatesServerSettings() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      return Self.response(
        for: request, status: 200,
        json:
          #"{"port":8787,"tmdb_configured":true,"tmdb_lang":"pt-BR","scan_every":"6h","tunnel_name":"casa","ffmpeg":true}"#
      )
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let loaded = try await client.settings(token: "session")
    let updated = try await client.updateSettings(
      SettingsUpdateRequest(
        tmdbKey: "segredo", tmdbLanguage: "pt-BR", scanInterval: "6h"),
      token: "session"
    )

    #expect(loaded.port == 8787)
    #expect(loaded.tmdbConfigured)
    #expect(updated.tunnelName == "casa")
    let recorded = await requests.requests
    #expect(recorded[1].httpMethod == "PUT")
    let body = try #require(recorded[1].httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["tmdb_key"] == "segredo")
    #expect(json["tmdb_lang"] == "pt-BR")
    #expect(json["scan_every"] == "6h")
  }

  @Test func searchesAndAppliesManualMatch() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      if request.httpMethod == "GET" {
        return Self.response(
          for: request, status: 200,
          json:
            #"{"results":[{"tmdb_id":99,"name":"Fundação & Império","year":2026,"overview":"Resultado correto","rating":8.8,"poster":"https://image.tmdb.org/poster.jpg"}]}"#
        )
      }
      return Self.response(for: request, status: 200, json: #"{"ok":true}"#)
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let candidates = try await client.matchCandidates(
      titleID: 7, query: "Fundação & Império", year: 2026, token: "session")
    try await client.applyMatch(titleID: 7, tmdbID: 99, token: "session")

    #expect(candidates.first?.tmdbID == 99)
    let recorded = await requests.requests
    let searchURL = try #require(recorded.first?.url)
    let components = try #require(URLComponents(url: searchURL, resolvingAgainstBaseURL: false))
    #expect(
      components.queryItems?.first(where: { $0.name == "q" })?.value == "Fundação & Império")
    #expect(components.queryItems?.first(where: { $0.name == "year" })?.value == "2026")
    #expect(recorded[1].url?.path == "/api/titles/7/match")
    let body = try #require(recorded[1].httpBody)
    let request = try JSONDecoder().decode(MatchRequest.self, from: body)
    #expect(request.tmdbID == 99)
  }

  @Test func parsesServerSentEventsWithMultipleDataLines() throws {
    var parser = ServerSentEventParser()

    #expect(parser.consume(": keep-alive") == nil)
    #expect(parser.consume("data: {\"status\":") == nil)
    #expect(parser.consume("data: \"ok\"}") == nil)
    let parsedEvent = parser.consume("")
    let event = try #require(parsedEvent)

    #expect(String(data: event, encoding: .utf8) == "{\"status\":\n\"ok\"}")
    #expect(parser.finish() == nil)
  }

  @Test func decodesAuthenticatedScanEventStream() async throws {
    let streamer = MockEventStreamer(payloads: [
      #"{"running":true,"stage":"arquivos","current":4,"total":9}"#,
      #"{"running":false,"last_stats":"9 arquivos"}"#,
    ])
    let client = APIClient(
      baseURL: baseURL,
      session: MockHTTPSession { request in
        Self.response(for: request, status: 500, json: #"{"error":"não deveria chamar"}"#)
      },
      eventStreamer: streamer
    )

    let stream = try client.scanEvents(token: "session")
    var received: [ScanStatus] = []
    for try await status in stream { received.append(status) }

    #expect(received.count == 2)
    #expect(received[0].current == 4)
    #expect(received[1].running == false)
    #expect(await streamer.lastAuthorization == "Bearer session")
    #expect(await streamer.lastAccept == "text/event-stream")
  }

  @Test func loadsArtistsAndEscapesNamesWithSlashes() async throws {
    let requests = RequestListRecorder()
    let session = MockHTTPSession { request in
      await requests.record(request)
      if request.url?.path == "/api/artistas" {
        return Self.response(
          for: request, status: 200,
          json:
            #"[{"nome":"AC/DC","albuns":2,"faixas":18,"duracao":3600,"poster":"/img/album/acdc"}]"#
        )
      }
      return Self.response(
        for: request, status: 200,
        json:
          #"{"nome":"AC/DC","albuns":[{"id":2,"library_id":2,"kind":"album","name":"Back in Black","year":1980,"artist":"AC/DC","files":1,"duration":255,"meta_state":"ready"}],"faixas":[{"id":20,"rel_path":"01.m4a","name":"Hells Bells","ext":"m4a","media_type":"audio","size":1024,"duration":255,"track":1}],"duracao":255}"#
      )
    }
    let client = APIClient(baseURL: baseURL, session: session)

    let artists = try await client.artists(token: "session")
    let detail = try await client.artist(name: "AC/DC", token: "session")

    #expect(artists.first?.name == "AC/DC")
    #expect(detail.tracks.first?.name == "Hells Bells")
    let recorded = await requests.requests
    let artistURL = try #require(recorded[1].url)
    let components = try #require(URLComponents(url: artistURL, resolvingAgainstBaseURL: false))
    #expect(components.percentEncodedPath == "/api/artistas/AC%2FDC")
    #expect(recorded[1].value(forHTTPHeaderField: "Authorization") == "Bearer session")
  }

  @Test func parsesISO8601WithAndWithoutFractionalSeconds() throws {
    let plain = try #require(ISO8601.date(from: "2026-08-28T12:00:00Z"))
    let fractional = try #require(ISO8601.date(from: "2026-08-28T12:00:00.250Z"))

    #expect(fractional.timeIntervalSince(plain) == 0.25)
    #expect(ISO8601.date(from: "ontem de manhã") == nil)
  }

  @Test func beginLoadingKeepsContentButReplacesIdleAndFailure() {
    var loaded = Loadable<Int>.loaded(7)
    loaded.beginLoading()
    #expect(loaded == .loaded(7))

    var idle = Loadable<Int>.idle
    idle.beginLoading()
    #expect(idle == .loading)

    var failed = Loadable<Int>.failed("erro")
    failed.beginLoading()
    #expect(failed == .loading)
  }

  @Test func catalogPaginationAppendsPagesAndIgnoresRepeatedTitles() throws {
    var content = CatalogContent(
      libraries: [], titles: try Self.page(ids: [1, 2], total: 3, offset: 0))
    #expect(content.items.count == 2)
    #expect(content.canLoadMore)

    content.append(try Self.page(ids: [2, 3], total: 3, offset: 2))

    #expect(content.items.map(\.id) == [1, 2, 3])
    #expect(content.canLoadMore == false)
  }

  @Test func catalogPaginationStopsWhenServerReturnsAnEmptyPage() throws {
    var content = CatalogContent(
      libraries: [], titles: try Self.page(ids: [1], total: 90, offset: 0))
    #expect(content.canLoadMore)

    content.append(try Self.page(ids: [], total: 90, offset: 1))

    #expect(content.canLoadMore == false)
    #expect(content.total == 1)
  }

  static func page(ids: [Int], total: Int, offset: Int) throws -> TitlesResponse {
    let items = ids.map {
      #"{"id":\#($0),"library_id":1,"kind":"movie","name":"Título \#($0)","files":1,"meta_state":"ready"}"#
    }
    let json = #"{"items":[\#(items.joined(separator: ","))],"total":\#(total),"offset":\#(offset),"limit":2}"#
    return try JSONDecoder().decode(TitlesResponse.self, from: Data(json.utf8))
  }

  @Test func decidesToPlayPrepareOrFailFromThePlan() throws {
    let direct = try Self.plan(mode: "direct", url: "/stream/70")
    #expect(PlaybackPlanner.decide(direct) == .play("/stream/70"))

    let pending = try Self.plan(mode: "remux", url: "", ffmpeg: true, transcoding: true)
    #expect(PlaybackPlanner.decide(pending) == .prepare("motivo"))

    let brokenDirect = try Self.plan(mode: "direct", url: "")
    #expect(PlaybackPlanner.decide(brokenDirect) == .failure(.missingURL))

    let noFFmpeg = try Self.plan(mode: "remux", url: "", ffmpeg: false, transcoding: true)
    #expect(PlaybackPlanner.decide(noFFmpeg) == .failure(.ffmpegUnavailable("motivo")))

    let disabled = try Self.plan(mode: "remux", url: "", ffmpeg: true, transcoding: false)
    #expect(PlaybackPlanner.decide(disabled) == .failure(.transcodingDisabled("motivo")))
  }

  @Test func mediaTokenReplacesAnyPreviousTokenInTheQuery() throws {
    let base = URL(string: "http://localhost:8787")!

    let fresh = try PlaybackPlanner.authorizedMediaURL(
      path: "/stream/70", relativeTo: base, token: "abc", parameter: "t")
    #expect(fresh.absoluteString == "http://localhost:8787/stream/70?t=abc")

    let renewed = try PlaybackPlanner.authorizedMediaURL(
      path: "/preparado/70?audio=3&t=velho", relativeTo: base, token: "novo", parameter: "t")
    let items = try #require(
      URLComponents(url: renewed, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.filter { $0.name == "t" }.map(\.value) == ["novo"])
    #expect(items.first { $0.name == "audio" }?.value == "3")
  }

  @Test func mediaTokenIsRenewedBeforeItLapses() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let absolute = try Self.mediaToken(expiresAt: "2026-08-28T12:00:00.500Z", validFor: 7200)
    #expect(PlaybackPlanner.expiry(of: absolute, now: now) == ISO8601.date(from: "2026-08-28T12:00:00.500Z"))

    // Sem data utilizável, vale a duração relativa informada pelo servidor.
    let relative = try Self.mediaToken(expiresAt: "sempre", validFor: 7200)
    #expect(PlaybackPlanner.expiry(of: relative, now: now) == now.addingTimeInterval(7200))

    #expect(PlaybackPlanner.needsRenewal(expiry: now.addingTimeInterval(60), now: now))
    #expect(PlaybackPlanner.needsRenewal(expiry: now.addingTimeInterval(600), now: now) == false)
    #expect(PlaybackPlanner.needsRenewal(expiry: now.addingTimeInterval(-1), now: now))
  }

  @Test func subtitleTimelineFindsTheCueCoveringTheInstant() {
    let timeline = SubtitleTimeline([
      SubtitleCue(start: 10, end: 12, text: "terceira"),
      SubtitleCue(start: 0, end: 2, text: "primeira"),
      SubtitleCue(start: 5, end: 6, text: "segunda"),
    ])

    #expect(timeline.text(at: 0) == "primeira")
    #expect(timeline.text(at: 1.9) == "primeira")
    #expect(timeline.text(at: 5.5) == "segunda")
    #expect(timeline.text(at: 11.99) == "terceira")
    // Buracos entre falas e além do fim não devem devolver a cue anterior.
    #expect(timeline.text(at: 3) == nil)
    #expect(timeline.text(at: 12) == nil)
    #expect(timeline.text(at: 900) == nil)
    #expect(SubtitleTimeline().text(at: 0) == nil)
  }

  static func plan(
    mode: String,
    url: String,
    ffmpeg: Bool = true,
    transcoding: Bool = true
  ) throws -> PlaybackPlan {
    let json = #"{"modo":"\#(mode)","motivo":"motivo","url":"\#(url)","url_direta":"/stream/70","ffmpeg":\#(ffmpeg),"transcodificacao_ativa":\#(transcoding)}"#
    return try JSONDecoder().decode(PlaybackPlan.self, from: Data(json.utf8))
  }

  static func mediaToken(expiresAt: String, validFor: Int) throws -> MediaTokenResponse {
    let json = #"{"token":"media","expira_em":"\#(expiresAt)","valido_por":\#(validFor),"param":"t"}"#
    return try JSONDecoder().decode(MediaTokenResponse.self, from: Data(json.utf8))
  }

  static func response(for request: URLRequest, status: Int, json: String) -> (Data, URLResponse) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(json.utf8), response)
  }
}

struct MockHTTPSession: HTTPSession {
  let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
    self.handler = handler
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await handler(request)
  }
}

private actor RequestRecorder {
  private(set) var request: URLRequest?
  func record(_ request: URLRequest) { self.request = request }
}

private actor RequestListRecorder {
  private(set) var requests: [URLRequest] = []
  func record(_ request: URLRequest) { requests.append(request) }
}

private actor AttemptCounter {
  private(set) var value = 0

  func increment() -> Int {
    value += 1
    return value
  }
}

private actor MockEventStreamer: EventStreaming {
  let payloads: [String]
  private(set) var lastAuthorization: String?
  private(set) var lastAccept: String?

  init(payloads: [String]) {
    self.payloads = payloads
  }

  nonisolated func events(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      Task {
        await record(request)
        for payload in payloads { continuation.yield(Data(payload.utf8)) }
        continuation.finish()
      }
    }
  }

  private func record(_ request: URLRequest) {
    lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
    lastAccept = request.value(forHTTPHeaderField: "Accept")
  }
}

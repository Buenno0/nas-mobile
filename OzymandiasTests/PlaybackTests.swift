import Foundation
import Testing

@testable import Ozymandias

// MARK: - Fila

struct PlaybackQueueTests {
  @Test func emptyQueueFallsBackToTheChosenFile() {
    let file = makeFile(id: 10)
    let queue = PlaybackQueue(items: [], startingAt: file)
    #expect(queue.items.map(\.id) == [10])
    #expect(queue.index == 0)
    #expect(!queue.hasNext)
    #expect(!queue.hasPrevious)
  }

  @Test func queueStartsAtTheChosenFileEvenWhenItIsNotTheFirst() {
    let files = [makeFile(id: 1), makeFile(id: 2), makeFile(id: 3)]
    let queue = PlaybackQueue(items: files, startingAt: files[1])
    #expect(queue.index == 1)
    #expect(queue.current?.id == 2)
    #expect(queue.hasNext)
    #expect(queue.hasPrevious)
  }

  @Test func advanceAndRewindStopAtTheBoundaries() {
    let files = [makeFile(id: 1), makeFile(id: 2)]
    var queue = PlaybackQueue(items: files, startingAt: files[0])
    #expect(queue.advance()?.id == 2)
    #expect(queue.advance() == nil)
    #expect(queue.index == 1)
    #expect(queue.rewind()?.id == 1)
    #expect(queue.rewind() == nil)
    #expect(queue.index == 0)
  }

  /// Um arquivo que não está na lista não pode deixar o índice fora de faixa.
  @Test func aFileOutsideTheListStartsAtTheBeginning() {
    let files = [makeFile(id: 1), makeFile(id: 2)]
    let queue = PlaybackQueue(items: files, startingAt: makeFile(id: 99))
    #expect(queue.index == 0)
    #expect(queue.current?.id == 1)
  }
}

// MARK: - Montagem da fila

struct PlaybackQueueBuilderTests {
  @Test func albumTrackEnqueuesTheWholeAlbumInTrackOrder() {
    let tracks = [
      makeFile(id: 21, mediaType: .audio, track: 2),
      makeFile(id: 20, mediaType: .audio, track: 1),
      makeFile(id: 22, mediaType: .audio, track: 3),
    ]
    let album = makeDetail(kind: .album, files: tracks)
    let queue = PlaybackQueueBuilder.queue(for: album, startingAt: tracks[0])
    #expect(queue.map(\.id) == [20, 21, 22])
  }

  @Test func aSingleTrackAlbumNeedsNoQueue() {
    let track = makeFile(id: 20, mediaType: .audio, track: 1)
    let album = makeDetail(kind: .album, files: [track])
    #expect(PlaybackQueueBuilder.queue(for: album, startingAt: track).isEmpty)
  }

  @Test func tracksWithoutNumberGoLast() {
    let tracks = [
      makeFile(id: 30, mediaType: .audio, track: nil),
      makeFile(id: 31, mediaType: .audio, track: 1),
    ]
    let album = makeDetail(kind: .album, files: tracks)
    #expect(PlaybackQueueBuilder.queue(for: album, startingAt: tracks[1]).map(\.id) == [31, 30])
  }

  /// Vídeo continua a cargo do `/next` do servidor, que sabe o que uma lista
  /// local não sabe. Montar fila aqui atropelaria essa decisão.
  @Test func videoBuildsNoQueue() {
    let episodes = [
      makeFile(id: 40, mediaType: .video, episode: 1),
      makeFile(id: 41, mediaType: .video, episode: 2),
    ]
    let series = makeDetail(kind: .tv, files: episodes)
    #expect(PlaybackQueueBuilder.queue(for: series, startingAt: episodes[0]).isEmpty)
  }

  @Test func photosAreNeverEnqueued() {
    let photo = makeFile(id: 50, mediaType: .photo)
    let album = makeDetail(kind: .photos, files: [photo, makeFile(id: 51, mediaType: .photo)])
    #expect(PlaybackQueueBuilder.queue(for: album, startingAt: photo).isEmpty)
  }
}

// MARK: - Seleção de áudio

struct AudioSelectionTests {
  /// A garantia central: no automático nenhum índice vai na requisição, então o
  /// servidor continua entregando o material que já preparou.
  @Test func automaticSendsNoParameterButStillReportsWhatItResolved() {
    let selection = AudioSelection.automatic(resolved: 3)
    #expect(selection.requestValue == nil)
    #expect(selection.displayIndex == 3)
    #expect(selection.isAutomatic)
  }

  @Test func explicitSendsTheIndex() {
    let selection = AudioSelection.explicit(2)
    #expect(selection.requestValue == 2)
    #expect(selection.displayIndex == 2)
    #expect(!selection.isAutomatic)
  }
}

struct PreferredAudioTrackTests {
  @Test func theServerDefaultWins() {
    let tracks = [
      makeTrack(index: 1, language: "eng", label: "Inglês", channels: 6),
      makeTrack(index: 2, language: "por", label: "Português", isDefault: true),
    ]
    let chosen = PlaybackPlanner.preferredAudioTrack(in: tracks, preferredLanguages: ["en"])
    #expect(chosen?.index == 2)
  }

  @Test func withoutADefaultTheDeviceLanguageWins() {
    let tracks = [
      makeTrack(index: 1, language: "eng", label: "Inglês"),
      makeTrack(index: 2, language: "por", label: "Português"),
    ]
    let chosen = PlaybackPlanner.preferredAudioTrack(in: tracks, preferredLanguages: ["pt-BR"])
    #expect(chosen?.index == 2)
  }

  @Test func channelsBreakTheTieWithinTheSameLanguage() {
    let tracks = [
      makeTrack(index: 1, language: "por", label: "Português", channels: 2),
      makeTrack(index: 2, language: "por", label: "Português", channels: 6),
    ]
    let chosen = PlaybackPlanner.preferredAudioTrack(in: tracks, preferredLanguages: ["pt-BR"])
    #expect(chosen?.index == 2)
  }

  @Test func aForcedTrackNeverWinsOnItsOwn() {
    let tracks = [
      makeTrack(index: 1, language: "por", label: "Comentários", isDefault: true, isForced: true),
      makeTrack(index: 2, language: "eng", label: "Inglês"),
    ]
    let chosen = PlaybackPlanner.preferredAudioTrack(in: tracks, preferredLanguages: ["pt-BR"])
    #expect(chosen?.index == 2)
  }

  @Test func noTracksMeansNoChoice() {
    #expect(PlaybackPlanner.preferredAudioTrack(in: [], preferredLanguages: ["pt-BR"]) == nil)
  }

  /// O ffprobe manda ISO 639-2/B e o sistema fala BCP-47; sem normalizar, nada
  /// de idioma casa.
  @Test func languageCodesNormalizeAcrossStandards() {
    #expect(PlaybackPlanner.normalizedLanguage("por") == "pt")
    #expect(PlaybackPlanner.normalizedLanguage("pt-BR") == "pt")
    #expect(PlaybackPlanner.normalizedLanguage("eng") == "en")
    #expect(PlaybackPlanner.normalizedLanguage("en-US") == "en")
    #expect(PlaybackPlanner.normalizedLanguage(nil) == nil)
    #expect(PlaybackPlanner.normalizedLanguage("") == nil)
  }
}

struct AudioTrackLabelTests {
  @Test func channelsAreAppendedOnlyWhenTheServerOmitsThem() {
    let already = makeTrack(index: 1, label: "Português · estéreo", channels: 2)
    #expect(PlaybackPlanner.audioTrackLabel(for: already) == "Português · estéreo")

    let missing = makeTrack(index: 2, label: "Português", channels: 6)
    #expect(PlaybackPlanner.audioTrackLabel(for: missing) == "Português · 5.1")
  }

  @Test func defaultAndForcedAreMarked() {
    let track = makeTrack(index: 1, label: "Português", isDefault: true, isForced: true)
    #expect(PlaybackPlanner.audioTrackLabel(for: track) == "Português · padrão · forçada")
  }

  @Test func channelCountsHaveNames() {
    #expect(PlaybackPlanner.channelLabel(1) == "mono")
    #expect(PlaybackPlanner.channelLabel(2) == "estéreo")
    #expect(PlaybackPlanner.channelLabel(6) == "5.1")
    #expect(PlaybackPlanner.channelLabel(8) == "7.1")
    #expect(PlaybackPlanner.channelLabel(3) == "3 canais")
  }
}

// MARK: - Interrupções

struct InterruptionPolicyTests {
  @Test func aCallPausesAndGivesPlaybackBack() {
    #expect(InterruptionPolicy.command(for: .interruption(.began), wasPlaying: true) == .pause)
    #expect(
      InterruptionPolicy.command(for: .interruption(.ended(shouldResume: true)), wasPlaying: true)
        == .resume)
  }

  @Test func whatWasPausedStaysPaused() {
    #expect(InterruptionPolicy.command(for: .interruption(.began), wasPlaying: false) == .none)
    #expect(
      InterruptionPolicy.command(for: .interruption(.ended(shouldResume: true)), wasPlaying: false)
        == .none)
    #expect(
      InterruptionPolicy.command(for: .interruption(.ended(shouldResume: false)), wasPlaying: true)
        == .none)
  }

  /// Tirar o fone pausa; recolocar não retoma sozinho, senão o som sai no
  /// alto-falante sem ninguém pedir.
  @Test func unpluggingPausesAndPluggingBackDoesNotResume() {
    #expect(InterruptionPolicy.command(for: .routeChanged(.outputDisconnected), wasPlaying: true) == .pause)
    #expect(InterruptionPolicy.command(for: .routeChanged(.outputConnected), wasPlaying: true) == .none)
    #expect(InterruptionPolicy.command(for: .routeChanged(.other), wasPlaying: true) == .none)
  }

  @Test func aMediaServicesResetAsksForAReload() {
    #expect(InterruptionPolicy.command(for: .mediaServicesReset, wasPlaying: false) == .reload)
  }
}

// MARK: - Progresso

struct ProgressCheckpointTests {
  @Test func invalidPositionsAreNeverPersisted() {
    #expect(!ProgressCheckpoint.shouldPersist(position: .nan, duration: 100, lastPersisted: nil))
    #expect(!ProgressCheckpoint.shouldPersist(position: -1, duration: 100, lastPersisted: nil))
    #expect(!ProgressCheckpoint.shouldPersist(position: 10, duration: 0, lastPersisted: nil))
    #expect(!ProgressCheckpoint.shouldPersist(position: 10, duration: .infinity, lastPersisted: nil))
  }

  @Test func theFirstPositionAlwaysCounts() {
    #expect(ProgressCheckpoint.shouldPersist(position: 12, duration: 100, lastPersisted: nil))
  }

  @Test func tinyMovesAreNotWorthARoundTrip() {
    #expect(!ProgressCheckpoint.shouldPersist(position: 12, duration: 100, lastPersisted: 11))
    #expect(ProgressCheckpoint.shouldPersist(position: 15, duration: 100, lastPersisted: 11))
  }

  /// O fim do arquivo é o que marca "assistido"; ele passa mesmo colado no
  /// último ponto gravado.
  @Test func reachingTheEndAlwaysCounts() {
    #expect(ProgressCheckpoint.shouldPersist(position: 100, duration: 100, lastPersisted: 99))
  }
}

// MARK: - Descoberta na rede

struct ServerDiscoveryTests {
  @Test func aResolvedHostBecomesAUsableAddress() {
    #expect(ServerDiscovery.serverAddress(host: "ozymandias.local", port: 8787)
      == "http://ozymandias.local:8787")
    #expect(ServerDiscovery.serverAddress(host: "192.168.1.20", port: 8787)
      == "http://192.168.1.20:8787")
  }

  /// O Bonjour devolve o nome com o ponto final do DNS e os endereços com o
  /// sufixo da interface; nenhum dos dois pode chegar na URL.
  @Test func theDNSDotAndTheInterfaceSuffixAreStripped() {
    #expect(ServerDiscovery.serverAddress(host: "ozymandias.local.", port: 8787)
      == "http://ozymandias.local:8787")
    #expect(ServerDiscovery.serverAddress(host: "fe80::1%en0", port: 8787)
      == "http://[fe80::1]:8787")
  }

  @Test func ipv6NeedsBrackets() {
    #expect(ServerDiscovery.serverAddress(host: "fd00::5", port: 8787)
      == "http://[fd00::5]:8787")
  }

  @Test func nothingUsableProducesNoAddress() {
    #expect(ServerDiscovery.serverAddress(host: "", port: 8787) == nil)
    #expect(ServerDiscovery.serverAddress(host: ".", port: 8787) == nil)
    #expect(ServerDiscovery.serverAddress(host: "ozymandias.local", port: 0) == nil)
  }

  /// O que a busca entrega tem de passar pela mesma validação do que é digitado
  /// à mão — a descoberta é um atalho, não uma porta dos fundos.
  @Test func discoveredAddressesSurviveNormalization() throws {
    let address = try #require(
      ServerDiscovery.serverAddress(host: "ozymandias.local.", port: 8787))
    #expect(try ServerAddress.normalize(address).absoluteString == "http://ozymandias.local:8787")
  }
}

// MARK: - Construtores

private func makeFile(
  id: Int,
  mediaType: MediaType = .video,
  track: Int? = nil,
  episode: Int? = nil,
  duration: Double = 120
) -> MediaFileInfo {
  MediaFileInfo(
    id: id,
    relPath: "arquivo-\(id)",
    name: "Arquivo \(id)",
    ext: mediaType == .audio ? ".m4a" : ".mp4",
    mediaType: mediaType,
    size: 1024,
    duration: duration,
    width: nil,
    height: nil,
    videoCodec: nil,
    audioCodec: nil,
    track: track,
    thumb: nil,
    position: nil,
    finished: nil,
    season: episode == nil ? nil : 1,
    episode: episode,
    episodeName: nil,
    capturedAt: nil,
    titleID: nil,
    titleName: nil,
    titleKind: nil,
    poster: nil
  )
}

private func makeDetail(kind: TitleKind, files: [MediaFileInfo]) -> TitleDetail {
  TitleDetail(
    id: 1,
    libraryID: 1,
    kind: kind,
    name: "Título",
    year: 2026,
    overview: nil,
    rating: nil,
    genres: nil,
    artist: nil,
    metaState: "ready",
    posterURL: nil,
    backdropURL: nil,
    library: "Biblioteca",
    favorite: false,
    files: files,
    seasons: nil
  )
}

private func makeTrack(
  index: Int,
  language: String? = nil,
  label: String,
  channels: Int? = nil,
  isDefault: Bool? = nil,
  isForced: Bool? = nil
) -> MediaTrack {
  MediaTrack(
    index: index,
    codec: "aac",
    language: language,
    label: label,
    channels: channels,
    isDefault: isDefault,
    isForced: isForced,
    isExternal: nil,
    url: nil,
    unavailableReason: nil
  )
}

struct UnavailablePlaybackTests {
  private func plan(_ json: String) throws -> PlaybackPlan {
    try JSONDecoder().decode(PlaybackPlan.self, from: Data(json.utf8))
  }

  @Test func aCloudOnlyItemInLocalModeExplainsWhy() throws {
    let p = try plan(#"{"modo":"direct","motivo":"na nuvem, indisponível no modo local","url":"","url_direta":"/stream/7","ffmpeg":true,"transcodificacao_ativa":true,"localizacao":"nuvem","indisponivel":true}"#)
    guard case .failure(.unavailable(let message)) = PlaybackPlanner.decide(p) else {
      Issue.record("Deveria ser indisponível, não sem URL")
      return
    }
    #expect(message.contains("só na nuvem"))
  }

  @Test func oldServersWithoutTheFieldStillPlay() throws {
    let p = try plan(#"{"modo":"direct","motivo":"ok","url":"/stream/7","url_direta":"/stream/7","ffmpeg":true,"transcodificacao_ativa":true}"#)
    #expect(PlaybackPlanner.decide(p) == .play("/stream/7"))
  }

  @Test func theWorkerPreparationHasNoPercentage() throws {
    let json = #"{"estado":"trabalhando","receita":"nuvem","segundos_prontos":0,"segundos_total":6000,"percentual":0,"velocidade":0,"restante_segundos":0}"#
    let progress = try JSONDecoder().decode(PreparationProgress.self, from: Data(json.utf8))
    #expect(PlaybackPlanner.isCloudPreparation(progress))
  }
}

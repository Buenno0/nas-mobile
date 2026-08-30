import SwiftUI
import UIKit

@main
struct OzymandiasApp: App {
  @State private var store: SessionStore
  @AppStorage("appearancePreference") private var appearancePreference = "dark"

  init() {
    let history = ServerHistory(defaults: .standard)
    let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let credentialStore: any CredentialStoring
    let sessionFactory: @Sendable (URL) -> any HTTPSession
    let eventStreamFactory: @Sendable (URL) -> any EventStreaming
    if isUITesting {
      credentialStore = UITestCredentialStore()
      sessionFactory = { _ in UITestHTTPSession() }
      eventStreamFactory = { _ in UITestEventStreamer() }
    } else {
      credentialStore = KeychainCredentialStore()
      sessionFactory = { _ in URLSession.shared }
      eventStreamFactory = { _ in URLSessionEventStreamer() }
    }
    _store = State(
      initialValue: SessionStore(
        credentialStore: credentialStore,
        history: history,
        sessionFactory: sessionFactory,
        eventStreamFactory: eventStreamFactory
      ))
  }

  var body: some Scene {
    WindowGroup {
      RootView(store: store)
        .preferredColorScheme(preferredScheme)
        .task { await store.restoreIfNeeded() }
    }
  }

  private var preferredScheme: ColorScheme? {
    switch appearancePreference {
    case "light": .light
    case "system": nil
    default: .dark
    }
  }
}

private struct UITestCredentialStore: CredentialStoring {
  func load() throws -> SessionCredential? { nil }
  func save(_ credential: SessionCredential) throws {}
  func clear() throws {}
}

private struct UITestHTTPSession: HTTPSession {
  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let path = request.url?.path ?? ""
    let body: String
    switch path {
    case "/healthz":
      body = #"{"status":"ok","time":"2026-08-28T12:00:00Z"}"#
    case "/api/auth/login":
      body =
        #"{"username":"teste","must_change_password":false,"is_admin":true,"token":"ui-token","expira_em":"2099-08-28T12:00:00Z"}"#
    case "/api/auth/me":
      body = #"{"username":"teste","must_change_password":false,"is_admin":true}"#
    case "/api/auth/logout":
      body = #"{"ok":true}"#
    case "/api/auth/media-token":
      body =
        #"{"token":"ui-media-token","expira_em":"2099-08-28T12:00:00Z","valido_por":7200,"param":"t"}"#
    case "/api/home":
      body =
        #"{"hero":{"id":1,"library_id":1,"kind":"movie","name":"Ozymandias","year":2026,"files":1,"duration":7200,"meta_state":"ready","poster":"/img/poster/1","backdrop":"/img/backdrop/1","genres":"Drama, Ficção"},"continue":[],"rows":[{"key":"recent","title":"Adicionados recentemente","items":[{"id":1,"library_id":1,"kind":"movie","name":"Ozymandias","year":2026,"files":1,"duration":7200,"meta_state":"ready","poster":"/img/poster/1"}]}]}"#
    case "/api/artistas":
      body =
        #"[{"nome":"Artista Teste","albuns":1,"faixas":2,"duracao":420,"poster":"/img/album/teste"}]"#
    case "/api/artistas/Artista%20Teste", "/api/artistas/Artista Teste":
      body =
        #"{"nome":"Artista Teste","albuns":[{"id":2,"library_id":2,"kind":"album","name":"Álbum Teste","year":2026,"artist":"Artista Teste","files":2,"duration":420,"meta_state":"ready"}],"faixas":[{"id":20,"rel_path":"faixa-1.m4a","name":"Primeira faixa","ext":"m4a","media_type":"audio","size":1024,"duration":180,"track":1},{"id":21,"rel_path":"faixa-2.m4a","name":"Segunda faixa","ext":"m4a","media_type":"audio","size":1024,"duration":240,"track":2}],"duracao":420}"#
    case "/api/libraries":
      body = #"[{"id":1,"name":"Filmes","kind":"movie","enabled":true}]"#
    case "/api/colecoes":
      body = #"[]"#
    case "/api/scan/status":
      body =
        #"{"running":false,"last_stats":"3 títulos · 4 arquivos","last_run":"2026-08-28T12:00:00Z"}"#
    case "/api/scan", "/api/metadata":
      body = #"{"started":true}"#
    case "/api/metrics/status":
      body =
        #"{"uptime_segundos":7200,"modo":"local","processo":{"cpu_percent":2.5,"cpu_nucleos":0.1,"heap_bytes":10485760,"rss_pico_bytes":20971520,"goroutines":12,"nucleos":8},"disco_livre_bytes":500000000000,"disco_total_bytes":1000000000000,"disco_reserva_bytes":10000000000,"cache_usado_bytes":100000000,"cache_limite_bytes":1000000000,"trafego":{"total":20,"erros":1,"taxa_erro":0.05,"rotas":[]}}"#
    case "/api/settings":
      body =
        #"{"port":8787,"tmdb_configured":true,"tmdb_lang":"pt-BR","scan_every":"1h","ffmpeg":true}"#
    case "/api/titles":
      body =
        // Dois títulos com nomes de comprimento diferente: é essa combinação que
        // desalinhava as células da grade (uma quebra em duas linhas, a outra não).
        #"{"items":[{"id":1,"library_id":1,"kind":"movie","name":"Ozymandias e o Deserto Infinito","year":2026,"files":1,"duration":7200,"meta_state":"ready","poster":"/img/poster/1"},{"id":2,"library_id":1,"kind":"movie","name":"Duna","year":2024,"files":1,"duration":9000,"meta_state":"ready","poster":"/img/poster/2"}],"total":2,"offset":0,"limit":60}"#
    case "/api/titles/1":
      body =
        #"{"id":1,"library_id":1,"kind":"movie","name":"Ozymandias","year":2026,"overview":"Um filme disponível na sua própria rede.","rating":8.4,"genres":"Drama, Ficção","meta_state":"matched","poster_url":"/img/poster/1","backdrop_url":"/img/backdrop/1","library":"Filmes","favorite":false,"files":[{"id":10,"rel_path":"Ozymandias.2026.1080p.WEB-DL.EAC3.mp4","name":"Ozymandias.2026.1080p.WEB-DL.EAC3.NACIONAL","ext":".mp4","media_type":"video","size":1024,"duration":7200,"height":1080,"width":1920,"position":5040}]}"#
    case "/api/titles/1/matches":
      body =
        #"{"results":[{"tmdb_id":99,"name":"Ozymandias","year":2026,"overview":"O resultado correto.","rating":8.8}]}"#
    case "/api/titles/1/match":
      body = #"{"ok":true}"#
    case "/api/titles/1/colecoes":
      body = #"{"colecoes":[]}"#
    case "/api/favorites/1":
      body = #"{"favorite":true}"#
    case "/api/files/10/playback":
      body =
        #"{"modo":"direct","motivo":"compatível","url":"/stream/10","url_direta":"/stream/10","ffmpeg":true,"transcodificacao_ativa":true}"#
    case "/api/files/20/playback":
      body =
        #"{"modo":"direct","motivo":"compatível","url":"/stream/20","url_direta":"/stream/20","ffmpeg":true,"transcodificacao_ativa":true}"#
    case "/api/files/10/faixas":
      body =
        #"{"audio":[{"idx":1,"codec":"aac","lang":"por","rotulo":"Português · estéreo","padrao":true}],"legendas":[{"idx":2,"codec":"subrip","lang":"por","rotulo":"Português","url":"/api/files/10/legenda/2.vtt"}]}"#
    case "/api/files/20/faixas":
      body = #"{"audio":[],"legendas":[]}"#
    case "/api/files/10/next":
      body = #"{"next":null}"#
    case "/api/files/20/next":
      body = #"{"next":null}"#
    case "/api/files/10/legenda/2.vtt":
      body = "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nLegenda de teste"
    case "/api/progress/10":
      body = #"{}"#
    case "/api/progress/20":
      body = #"{}"#
    default:
      body = #"{"error":"rota não encontrada"}"#
    }
    if path.hasPrefix("/img/") {
      let landscape = path.contains("backdrop")
      let data = Self.artwork(landscape: landscape)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "image/png"]
      )!
      return (data, response)
    }

    let status = path == "/healthz" || path.hasPrefix("/api/") ? 200 : 404
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(body.utf8), response)
  }
}

extension UITestHTTPSession {
  /// Arte sintética clara — céu, mar e areia, com um sol forte no alto. É o pior
  /// caso para a legibilidade do texto sobre o banner, que é o que as capturas
  /// dos testes precisam exercitar.
  static func artwork(landscape: Bool) -> Data {
    let size = landscape ? CGSize(width: 900, height: 600) : CGSize(width: 600, height: 900)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.pngData { context in
      let cg = context.cgContext
      let colors =
        [
          UIColor(red: 0.51, green: 0.75, blue: 0.95, alpha: 1).cgColor,
          UIColor(red: 0.36, green: 0.63, blue: 0.87, alpha: 1).cgColor,
          UIColor(red: 0.10, green: 0.33, blue: 0.52, alpha: 1).cgColor,
          UIColor(red: 0.85, green: 0.78, blue: 0.63, alpha: 1).cgColor,
          UIColor(red: 0.92, green: 0.87, blue: 0.75, alpha: 1).cgColor,
        ] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.42, 0.55, 0.62, 1]
      ) {
        cg.drawLinearGradient(
          gradient,
          start: .zero,
          end: CGPoint(x: 0, y: size.height),
          options: []
        )
      }

      let sun = CGPoint(x: size.width * 0.78, y: size.height * 0.14)
      if let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
          UIColor(white: 1, alpha: 0.95).cgColor,
          UIColor(white: 1, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1]
      ) {
        cg.drawRadialGradient(
          glow,
          startCenter: sun,
          startRadius: 0,
          endCenter: sun,
          endRadius: size.width * 0.42,
          options: []
        )
      }
    }
  }
}

private struct UITestEventStreamer: EventStreaming {
  func events(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      switch request.url?.path {
      case "/api/scan/events":
        continuation.yield(
          Data(
            #"{"running":false,"last_stats":"3 títulos · 4 arquivos","last_run":"2026-08-28T12:00:00Z"}"#
              .utf8
          ))
      case "/api/metrics/events":
        continuation.yield(
          Data(
            #"{"uptime_segundos":7200,"modo":"local","processo":{"cpu_percent":2.5,"cpu_nucleos":0.1,"heap_bytes":10485760,"rss_pico_bytes":20971520,"goroutines":12,"nucleos":8},"disco_livre_bytes":500000000000,"disco_total_bytes":1000000000000,"disco_reserva_bytes":10000000000,"cache_usado_bytes":100000000,"cache_limite_bytes":1000000000,"trafego":{"total":20,"erros":1,"taxa_erro":0.05,"rotas":[]}}"#
              .utf8
          ))
      default:
        continuation.finish()
      }
    }
  }
}

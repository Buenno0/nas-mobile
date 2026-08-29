import SwiftUI

@main
struct OzymandiasApp: App {
  @State private var store: SessionStore
  @AppStorage("appearancePreference") private var appearancePreference = "dark"

  init() {
    let history = ServerHistory(defaults: .standard)
    let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let credentialStore: any CredentialStoring
    let sessionFactory: @Sendable (URL) -> any HTTPSession
    if isUITesting {
      credentialStore = UITestCredentialStore()
      sessionFactory = { _ in UITestHTTPSession() }
    } else {
      credentialStore = KeychainCredentialStore()
      sessionFactory = { _ in URLSession.shared }
    }
    _store = State(
      initialValue: SessionStore(
        credentialStore: credentialStore,
        history: history,
        sessionFactory: sessionFactory
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
    default:
      body = #"{"error":"rota não encontrada"}"#
    }
    let status = path == "/healthz" || path.hasPrefix("/api/auth/") ? 200 : 404
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(body.utf8), response)
  }
}

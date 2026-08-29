import Foundation
import Testing

@testable import Ozymandias

@MainActor
struct SessionStoreTests {
  @Test func restoresValidCredential() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "valid-token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { request in
      APIClientTests.response(
        for: request,
        status: 200,
        json: #"{"username":"ana","must_change_password":false,"is_admin":true}"#
      )
    }
    await store.restoreIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_000))
    guard case .authenticated(let session) = store.phase else {
      Issue.record("A sessão deveria ter sido restaurada")
      return
    }
    #expect(session.user.username == "ana")
  }

  @Test func expiredCredentialReturnsToLoginAndIsCleared() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "expired",
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { request in
      APIClientTests.response(for: request, status: 500, json: #"{"error":"não deveria chamar"}"#)
    }
    await store.restoreIfNeeded(now: Date(timeIntervalSince1970: 2))
    #expect(store.phase == .signedOut)
    #expect(try credentials.load() == nil)
  }

  @Test func unauthorizedRestoreClearsCredential() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "revoked",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { request in
      APIClientTests.response(for: request, status: 401, json: #"{"error":"não autenticado"}"#)
    }
    await store.restoreIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_000))
    #expect(store.phase == .signedOut)
    #expect(try credentials.load() == nil)
  }

  @Test func offlineRestorePreservesCredentialForRetry() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "still-valid",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { _ in throw URLError(.cannotConnectToHost) }
    await store.restoreIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_000))
    guard case .restoreFailed = store.phase else {
      Issue.record("A restauração offline deveria oferecer nova tentativa")
      return
    }
    #expect(try credentials.load() == credential)
  }

  @Test func keychainWritesReadsAndRemovesCredential() throws {
    let store = KeychainCredentialStore()
    try store.clear()
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "keychain-test-\(UUID().uuidString)",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    try store.save(credential)
    #expect(try store.load() == credential)
    try store.clear()
    #expect(try store.load() == nil)
  }

  @Test func loginPersistsCredentialAndEntersAuthenticatedState() async throws {
    let credentials = MemoryCredentialStore()
    let store = makeStore(credentials: credentials) { request in
      if request.url?.path == "/healthz" {
        return APIClientTests.response(
          for: request, status: 200, json: #"{"status":"ok","time":"now"}"#)
      }
      return APIClientTests.response(
        for: request,
        status: 200,
        json:
          #"{"username":"ana","must_change_password":false,"is_admin":true,"token":"saved-token","expira_em":"2099-08-28T12:00:00Z"}"#
      )
    }
    store.phase = .signedOut
    await store.validateServer()
    #expect(
      store.authenticationStep == .login(URL(string: "http://localhost:8787")!)
    )
    store.username = "ana"
    store.password = "password"
    await store.login(now: Date(timeIntervalSince1970: 2_000_000_000))
    guard case .authenticated = store.phase else {
      Issue.record("O login deveria autenticar")
      return
    }
    #expect(try credentials.load()?.token == "saved-token")
  }

  @Test func selectingAnotherServerReturnsToFirstStep() async {
    let store = makeStore(credentials: MemoryCredentialStore()) { request in
      APIClientTests.response(
        for: request, status: 200, json: #"{"status":"ok","time":"now"}"#)
    }
    store.phase = .signedOut
    await store.validateServer()
    guard case .login = store.authenticationStep else {
      Issue.record("A validação deveria abrir o login")
      return
    }

    store.showServerSelection()

    #expect(store.authenticationStep == .serverSelection)
    #expect(store.phase == .signedOut)
    #expect(store.isServerValidated == false)
  }

  @Test func logoutAlwaysClearsLocalCredential() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { _ in throw URLError(.cannotConnectToHost) }
    store.phase = .authenticated(
      AuthenticatedSession(
        user: UserResponse(
          username: "ana", mustChangePassword: false, isAdmin: true, token: nil, expiraEm: nil),
        credential: credential
      ))
    await store.logout()
    #expect(store.phase == .signedOut)
    #expect(try credentials.load() == nil)
  }

  private func makeStore(
    credentials: MemoryCredentialStore,
    handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ) -> SessionStore {
    let suite = "SessionStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SessionStore(
      credentialStore: credentials,
      history: ServerHistory(defaults: defaults),
      sessionFactory: { _ in MockHTTPSession(handler: handler) }
    )
  }
}

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var credential: SessionCredential?

  init(credential: SessionCredential? = nil) { self.credential = credential }

  func load() throws -> SessionCredential? {
    lock.withLock { credential }
  }

  func save(_ credential: SessionCredential) throws {
    lock.withLock { self.credential = credential }
  }

  func clear() throws {
    lock.withLock { credential = nil }
  }
}

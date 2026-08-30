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

  @Test func loadsHomeForAuthenticatedSession() async {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      APIClientTests.response(
        for: request,
        status: 200,
        json:
          #"{"hero":{"id":7,"library_id":2,"kind":"movie","name":"Duna","files":1,"meta_state":"ready"},"continue":[],"rows":[]}"#
      )
    }
    let session = AuthenticatedSession(
      user: UserResponse(
        username: "ana", mustChangePassword: false, isAdmin: false, token: nil, expiraEm: nil),
      credential: credential
    )

    await store.loadHome(for: session)

    guard case .loaded(let home) = store.homeState else {
      Issue.record("A Home deveria estar carregada")
      return
    }
    #expect(home.hero?.name == "Duna")
  }

  @Test func unauthorizedHomeInvalidatesSession() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "revoked",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let credentials = MemoryCredentialStore(credential: credential)
    let store = makeStore(credentials: credentials) { request in
      APIClientTests.response(for: request, status: 401, json: #"{"error":"não autenticado"}"#)
    }
    let session = AuthenticatedSession(
      user: UserResponse(
        username: "ana", mustChangePassword: false, isAdmin: false, token: nil, expiraEm: nil),
      credential: credential
    )
    store.phase = .authenticated(session)

    await store.loadHome(for: session)

    #expect(store.phase == .signedOut)
    // O endereço continua válido: só a credencial morreu.
    #expect(store.authenticationStep == .login(URL(string: "http://localhost:8787")!))
    #expect(store.isServerValidated)
    #expect(try credentials.load() == nil)
  }

  @Test func loginAcceptsExpirationWithFractionalSeconds() async throws {
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
          #"{"username":"ana","must_change_password":false,"is_admin":true,"token":"saved-token","expira_em":"2099-08-28T12:00:00.482Z"}"#
      )
    }
    store.phase = .signedOut
    await store.validateServer()
    store.username = "ana"
    store.password = "password"

    await store.login(now: Date(timeIntervalSince1970: 2_000_000_000))

    guard case .authenticated = store.phase else {
      Issue.record("Milissegundos em expira_em não podem impedir o login")
      return
    }
    #expect(try credentials.load()?.token == "saved-token")
  }

  @Test func loadMoreCatalogAppendsTheNextPage() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      if request.url?.path == "/api/libraries" {
        return APIClientTests.response(for: request, status: 200, json: "[]")
      }
      let offset =
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "offset" }?.value
      let json =
        offset == "2"
        ? #"{"items":[{"id":3,"library_id":1,"kind":"movie","name":"Terceiro","files":1,"meta_state":"ready"}],"total":3,"offset":2,"limit":2}"#
        : #"{"items":[{"id":1,"library_id":1,"kind":"movie","name":"Primeiro","files":1,"meta_state":"ready"},{"id":2,"library_id":1,"kind":"movie","name":"Segundo","files":1,"meta_state":"ready"}],"total":3,"offset":0,"limit":2}"#
      return APIClientTests.response(for: request, status: 200, json: json)
    }
    let session = AuthenticatedSession(
      user: UserResponse(
        username: "ana", mustChangePassword: false, isAdmin: false, token: nil, expiraEm: nil),
      credential: credential
    )
    let query = CatalogQuery(limit: 2)

    await store.loadCatalog(for: session, query: query)
    let firstPage = try #require(store.catalogState.value)
    #expect(firstPage.items.count == 2)
    #expect(firstPage.canLoadMore)

    await store.loadMoreCatalog(for: session, query: query)

    let complete = try #require(store.catalogState.value)
    #expect(complete.items.map(\.name) == ["Primeiro", "Segundo", "Terceiro"])
    #expect(complete.canLoadMore == false)
    #expect(store.catalogPageError == nil)
  }

  @Test func loadMoreCatalogSurfacesPageErrorsWithoutLosingTheList() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      if request.url?.path == "/api/libraries" {
        return APIClientTests.response(for: request, status: 200, json: "[]")
      }
      let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
      if components?.queryItems?.contains(where: { $0.name == "offset" }) == true {
        return APIClientTests.response(
          for: request, status: 500, json: #"{"error":"o servidor tropeçou"}"#)
      }
      return APIClientTests.response(
        for: request, status: 200,
        json:
          #"{"items":[{"id":1,"library_id":1,"kind":"movie","name":"Primeiro","files":1,"meta_state":"ready"}],"total":9,"offset":0,"limit":1}"#
      )
    }
    let session = AuthenticatedSession(
      user: UserResponse(
        username: "ana", mustChangePassword: false, isAdmin: false, token: nil, expiraEm: nil),
      credential: credential
    )
    let query = CatalogQuery(limit: 1)

    await store.loadCatalog(for: session, query: query)
    await store.loadMoreCatalog(for: session, query: query)

    #expect(store.catalogPageError == "o servidor tropeçou")
    #expect(store.catalogState.value?.items.count == 1)
  }

  @Test func cachedTitleIsNotFetchedTwiceButForceRefetches() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let counter = CallCounter()
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      await counter.record()
      return APIClientTests.response(
        for: request, status: 200,
        json:
          #"{"id":7,"library_id":1,"kind":"movie","name":"Duna","meta_state":"ready","library":"Filmes","favorite":false,"files":[]}"#
      )
    }
    let session = Self.session(credential)

    _ = try await store.title(id: 7, for: session)
    _ = try await store.title(id: 7, for: session)
    #expect(await counter.count == 1)

    _ = try await store.title(id: 7, for: session, force: true)
    #expect(await counter.count == 2)

    // Aplicar um match muda capa e metadados: o cache não pode sobreviver.
    store.invalidateContent()
    _ = try await store.title(id: 7, for: session)
    #expect(await counter.count == 3)
  }

  @Test func markingWatchedSavesProgressAtTheEndAndUnmarkingResetsIt() async throws {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let requests = BodyRecorder()
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      await requests.record(request)
      return APIClientTests.response(for: request, status: 200, json: "{}")
    }
    let session = Self.session(credential)
    let file = try Self.file(id: 70, duration: 9000)

    try await store.setWatched(true, file: file, for: session)
    try await store.setWatched(false, file: file, for: session)

    let bodies = await requests.bodies
    #expect(bodies.count == 2)
    let watched = try JSONDecoder().decode(ProgressRequest.self, from: bodies[0])
    let unwatched = try JSONDecoder().decode(ProgressRequest.self, from: bodies[1])
    #expect(watched.position == 9000)
    #expect(watched.duration == 9000)
    #expect(unwatched.position == 0)
    #expect(store.homeState == .idle)
  }

  @Test func playbackProgressKeepsLoadedHomeAndFailedRefreshDoesNotReplaceIt() async {
    let credential = SessionCredential(
      serverURL: URL(string: "http://localhost:8787")!,
      token: "token",
      expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
    let homeCalls = CallCounter()
    let store = makeStore(credentials: MemoryCredentialStore(credential: credential)) { request in
      if request.url?.path == "/api/home" {
        await homeCalls.record()
        if await homeCalls.count > 1 {
          throw URLError(.networkConnectionLost)
        }
        return APIClientTests.response(
          for: request, status: 200,
          json:
            #"{"hero":{"id":7,"library_id":2,"kind":"movie","name":"Duna","files":1,"meta_state":"ready"},"continue":[],"rows":[]}"#
        )
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
      return (Data(), response)
    }
    let session = Self.session(credential)

    await store.loadHome(for: session)
    await store.saveProgress(fileID: 70, position: 120, duration: 9000, for: session)

    #expect(store.homeState.value?.hero?.name == "Duna")

    await store.refreshHomeAfterPlayback(for: session)

    #expect(store.homeState.value?.hero?.name == "Duna")
    #expect(await homeCalls.count == 3)
  }

  private static func session(_ credential: SessionCredential) -> AuthenticatedSession {
    AuthenticatedSession(
      user: UserResponse(
        username: "ana", mustChangePassword: false, isAdmin: false, token: nil, expiraEm: nil),
      credential: credential
    )
  }

  private static func file(id: Int, duration: Double) throws -> MediaFileInfo {
    let json = #"{"id":\#(id),"rel_path":"a.mkv","name":"Duna","ext":"mkv","media_type":"video","size":1,"duration":\#(duration)}"#
    return try JSONDecoder().decode(MediaFileInfo.self, from: Data(json.utf8))
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

private actor CallCounter {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor BodyRecorder {
  private(set) var bodies: [Data] = []
  func record(_ request: URLRequest) {
    if let body = request.httpBody { bodies.append(body) }
  }
}

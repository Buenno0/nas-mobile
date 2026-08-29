import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
  enum AuthenticationStep: Equatable {
    case serverSelection
    case login(URL)
  }

  enum Phase: Equatable {
    case restoring
    case restoreFailed(String)
    case signedOut
    case authenticated(AuthenticatedSession)
    case passwordChangeRequired(AuthenticatedSession)
  }

  var phase: Phase = .restoring
  var authenticationStep: AuthenticationStep = .serverSelection
  var serverInput = ServerAddress.defaultValue
  var username = ""
  var password = ""
  var remember = true
  var isPasswordVisible = false
  var isValidatingServer = false
  var isServerValidated = false
  var isAuthenticating = false
  var isLoggingOut = false
  var errorMessage: String?
  private(set) var recentServers: [String]

  private let credentialStore: any CredentialStoring
  private let history: ServerHistory
  private let sessionFactory: @Sendable (URL) -> any HTTPSession
  private var didRestore = false

  init(
    credentialStore: any CredentialStoring,
    history: ServerHistory,
    sessionFactory: @escaping @Sendable (URL) -> any HTTPSession = { _ in URLSession.shared }
  ) {
    self.credentialStore = credentialStore
    self.history = history
    self.sessionFactory = sessionFactory
    self.recentServers = history.load()
  }

  func restoreIfNeeded(now: Date = .now) async {
    guard !didRestore else { return }
    didRestore = true
    do {
      guard let credential = try credentialStore.load() else {
        showServerSelection()
        return
      }
      serverInput = credential.serverURL.absoluteString
      guard credential.expiresAt > now else {
        try? credentialStore.clear()
        showServerSelection()
        return
      }
      let user = try await client(for: credential.serverURL).me(token: credential.token)
      let session = AuthenticatedSession(user: user, credential: credential)
      phase = user.mustChangePassword ? .passwordChangeRequired(session) : .authenticated(session)
    } catch let error as APIClientError where error.statusCode == 401 {
      try? credentialStore.clear()
      showServerSelection()
    } catch {
      phase = .restoreFailed(
        "Não foi possível confirmar sua sessão. Verifique se o servidor está ligado e tente novamente."
      )
    }
  }

  func retryRestore() async {
    didRestore = false
    phase = .restoring
    await restoreIfNeeded()
  }

  func discardStoredSession() {
    try? credentialStore.clear()
    showServerSelection()
  }

  func selectRecentServer(_ value: String) {
    serverInput = value
    isServerValidated = false
    errorMessage = nil
  }

  func serverDidChange() {
    isServerValidated = false
    errorMessage = nil
  }

  func validateServer() async {
    guard !isValidatingServer else { return }
    errorMessage = nil
    isServerValidated = false
    let url: URL
    do {
      url = try ServerAddress.normalize(serverInput)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    isValidatingServer = true
    defer { isValidatingServer = false }
    do {
      _ = try await client(for: url).health()
      serverInput = url.absoluteString
      isServerValidated = true
      history.remember(url)
      recentServers = history.load()
      authenticationStep = .login(url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func showServerSelection() {
    errorMessage = nil
    password = ""
    isServerValidated = false
    authenticationStep = .serverSelection
    phase = .signedOut
  }

  func login(now: Date = .now) async {
    guard !isAuthenticating else { return }
    errorMessage = nil
    let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanUsername.isEmpty, !password.isEmpty else {
      errorMessage = "Preencha usuário e senha."
      return
    }
    let url: URL
    do {
      url = try ServerAddress.normalize(serverInput)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    guard case .login(let selectedServer) = authenticationStep, selectedServer == url else {
      errorMessage = "Escolha e conecte-se a um servidor antes de entrar."
      return
    }

    isAuthenticating = true
    defer { isAuthenticating = false }
    do {
      let response = try await client(for: url).login(
        username: cleanUsername,
        password: password,
        remember: remember
      )
      guard let token = response.token,
        let expiration = response.expiraEm.flatMap(Self.parseDate),
        expiration > now
      else {
        throw APIClientError.invalidPayload
      }
      let credential = SessionCredential(serverURL: url, token: token, expiresAt: expiration)
      try credentialStore.save(credential)
      password = ""
      let session = AuthenticatedSession(user: response, credential: credential)
      phase =
        response.mustChangePassword ? .passwordChangeRequired(session) : .authenticated(session)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func logout() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    errorMessage = nil
    let session: AuthenticatedSession?
    switch phase {
    case .authenticated(let value), .passwordChangeRequired(let value): session = value
    default: session = nil
    }
    if let session {
      try? await client(for: session.credential.serverURL).logout(token: session.credential.token)
    }
    try? credentialStore.clear()
    showServerSelection()
    isLoggingOut = false
  }

  private func client(for url: URL) -> APIClient {
    APIClient(baseURL: url, session: sessionFactory(url))
  }

  private static func parseDate(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
  }
}

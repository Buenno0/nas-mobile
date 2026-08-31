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
  var homeState: Loadable<HomeResponse> = .idle
  var catalogState: Loadable<CatalogContent> = .idle
  private(set) var isLoadingMoreCatalog = false
  private(set) var catalogPageError: String?
  private(set) var recentServers: [String]

  private let credentialStore: any CredentialStoring
  private let history: ServerHistory
  private let sessionFactory: @Sendable (URL) -> any HTTPSession
  private let eventStreamFactory: @Sendable (URL) -> any EventStreaming
  private var didRestore = false
  private var loadedCatalogQuery: CatalogQuery?
  private var titleCache: [Int: TitleDetail] = [:]

  init(
    credentialStore: any CredentialStoring,
    history: ServerHistory,
    sessionFactory: @escaping @Sendable (URL) -> any HTTPSession = { _ in URLSession.shared },
    eventStreamFactory: @escaping @Sendable (URL) -> any EventStreaming = {
      _ in URLSessionEventStreamer()
    }
  ) {
    self.credentialStore = credentialStore
    self.history = history
    self.sessionFactory = sessionFactory
    self.eventStreamFactory = eventStreamFactory
    self.recentServers = history.load()
  }

  func restoreIfNeeded(now: Date = .now) async {
    guard !didRestore else { return }
    didRestore = true
    let stored = try? credentialStore.load()
    guard let credential = stored else {
      showServerSelection()
      return
    }
    serverInput = credential.serverURL.absoluteString
    guard credential.expiresAt > now else {
      try? credentialStore.clear()
      signOut(returningTo: credential.serverURL)
      return
    }
    do {
      let user = try await client(for: credential.serverURL).me(token: credential.token)
      let session = AuthenticatedSession(user: user, credential: credential)
      phase = user.mustChangePassword ? .passwordChangeRequired(session) : .authenticated(session)
    } catch let error as APIClientError where error.statusCode == 401 {
      try? credentialStore.clear()
      signOut(returningTo: credential.serverURL)
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
    signOut(returningTo: nil)
  }

  /// Uma sessão vencida ou revogada não invalida o endereço: o servidor
  /// continua bom, só as credenciais não. Voltar para a seleção de servidor
  /// obrigaria a revalidar tudo de novo à toa.
  func signOut(returningTo server: URL?) {
    errorMessage = nil
    password = ""
    isServerValidated = server != nil
    if let server {
      serverInput = server.absoluteString
      authenticationStep = .login(server)
    } else {
      authenticationStep = .serverSelection
    }
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

  func loadHome(for session: AuthenticatedSession, force: Bool = false) async {
    guard force || homeState == .idle else { return }
    let previousContent = homeState.value
    homeState.beginLoading()
    do {
      let content = try await client(for: session.credential.serverURL)
        .home(token: session.credential.token)
      homeState = .loaded(content)
    } catch {
      if await handleUnauthorizedContentError(error) { return }
      // Uma atualização da Home não deve apagar uma tela que já estava boa.
      // Isso é especialmente importante ao fechar o player, quando a rede pode
      // ainda estar retomando do background.
      if let previousContent {
        homeState = .loaded(previousContent)
      } else {
        homeState = .failed(error.localizedDescription)
      }
    }
  }

  /// Atualiza as posições de "Continuar assistindo" depois que o player fecha,
  /// preservando a Home atual se o servidor estiver momentaneamente ocupado.
  func refreshHomeAfterPlayback(for session: AuthenticatedSession) async {
    titleCache.removeAll()
    await loadHome(for: session, force: true)
  }

  func loadCatalog(
    for session: AuthenticatedSession,
    query: CatalogQuery = CatalogQuery(),
    force: Bool = false
  ) async {
    guard force || catalogState == .idle || loadedCatalogQuery != query else { return }
    loadedCatalogQuery = query
    catalogState.beginLoading()
    do {
      let api = client(for: session.credential.serverURL)
      async let libraries = api.libraries(token: session.credential.token)
      async let titles = api.titles(query: query, token: session.credential.token)
      let content = try await CatalogContent(libraries: libraries, titles: titles)
      guard loadedCatalogQuery == query else { return }
      catalogState = .loaded(content)
    } catch {
      if await handleUnauthorizedContentError(error) { return }
      guard loadedCatalogQuery == query else { return }
      catalogState = .failed(error.localizedDescription)
    }
  }

  /// Busca a próxima página do acervo e a anexa ao que já está na tela.
  func loadMoreCatalog(for session: AuthenticatedSession, query: CatalogQuery) async {
    guard !isLoadingMoreCatalog,
      loadedCatalogQuery == query,
      let content = catalogState.value,
      content.canLoadMore
    else { return }

    isLoadingMoreCatalog = true
    catalogPageError = nil
    defer { isLoadingMoreCatalog = false }

    var nextPage = query
    nextPage.offset = content.loadedCount
    do {
      let page = try await client(for: session.credential.serverURL)
        .titles(query: nextPage, token: session.credential.token)
      guard loadedCatalogQuery == query, var updated = catalogState.value else { return }
      updated.append(page)
      catalogState = .loaded(updated)
    } catch {
      if await handleUnauthorizedContentError(error) { return }
      guard loadedCatalogQuery == query else { return }
      catalogPageError = error.localizedDescription
    }
  }

  func collections(for session: AuthenticatedSession) async throws -> [MediaCollection] {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .collections(token: session.credential.token)
    }
  }

  func artists(for session: AuthenticatedSession) async throws -> [ArtistCard] {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .artists(token: session.credential.token)
    }
  }

  func artist(name: String, for session: AuthenticatedSession) async throws -> ArtistDetail {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .artist(name: name, token: session.credential.token)
    }
  }

  func collection(id: Int, for session: AuthenticatedSession) async throws -> CollectionContent {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .collection(id: id, token: session.credential.token)
    }
  }

  func createCollection(name: String, for session: AuthenticatedSession) async throws
    -> MediaCollection
  {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .createCollection(name: name, token: session.credential.token)
    }
  }

  func renameCollection(id: Int, name: String, for session: AuthenticatedSession) async throws {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .renameCollection(id: id, name: name, token: session.credential.token)
    }
  }

  func deleteCollection(id: Int, for session: AuthenticatedSession) async throws {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .deleteCollection(id: id, token: session.credential.token)
    }
  }

  func setCollectionMembership(
    collectionID: Int, titleID: Int, included: Bool, for session: AuthenticatedSession
  ) async throws {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL).setCollectionMembership(
        collectionID: collectionID,
        titleID: titleID,
        included: included,
        token: session.credential.token
      )
    }
  }

  func collectionIDs(titleID: Int, for session: AuthenticatedSession) async throws -> [Int] {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .collectionIDs(titleID: titleID, token: session.credential.token)
    }
  }

  func scanStatus(for session: AuthenticatedSession) async throws -> ScanStatus {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .scanStatus(token: session.credential.token)
    }
  }

  func startScan(for session: AuthenticatedSession) async throws {
    try await authenticatedContentRequest {
      _ = try await client(for: session.credential.serverURL)
        .startScan(token: session.credential.token)
    }
  }

  func refreshMetadata(all: Bool, for session: AuthenticatedSession) async throws {
    try await authenticatedContentRequest {
      _ = try await client(for: session.credential.serverURL)
        .refreshMetadata(all: all, token: session.credential.token)
    }
  }

  func metrics(for session: AuthenticatedSession) async throws -> MetricsSnapshot {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .metrics(token: session.credential.token)
    }
  }

  func scanEvents(for session: AuthenticatedSession) throws -> AsyncThrowingStream<
    ScanStatus, Error
  > {
    try client(for: session.credential.serverURL)
      .scanEvents(token: session.credential.token)
  }

  func metricEvents(for session: AuthenticatedSession) throws
    -> AsyncThrowingStream<MetricsSnapshot, Error>
  {
    try client(for: session.credential.serverURL)
      .metricEvents(token: session.credential.token)
  }

  func handleEventStreamError(_ error: Error) async -> Bool {
    await handleUnauthorizedContentError(error)
  }

  func settings(for session: AuthenticatedSession) async throws -> ServerSettings {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .settings(token: session.credential.token)
    }
  }

  func updateSettings(
    _ request: SettingsUpdateRequest, for session: AuthenticatedSession
  ) async throws -> ServerSettings {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .updateSettings(request, token: session.credential.token)
    }
  }

  func matchCandidates(
    titleID: Int, query: String, year: Int?, for session: AuthenticatedSession
  ) async throws -> [MatchCandidate] {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .matchCandidates(
          titleID: titleID, query: query, year: year, token: session.credential.token)
    }
  }

  func applyMatch(titleID: Int, tmdbID: Int, for session: AuthenticatedSession) async throws {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .applyMatch(titleID: titleID, tmdbID: tmdbID, token: session.credential.token)
    }
    invalidateContent()
  }

  /// O conteúdo mudou no servidor (match aplicado, metadados atualizados):
  /// recarrega as listas e descarta as artes, que podem ter trocado.
  func invalidateContent() {
    homeState = .idle
    catalogState = .idle
    loadedCatalogQuery = nil
    catalogPageError = nil
    titleCache.removeAll()
    Task { await ArtworkCache.shared.clear() }
  }

  func imageData(path: String, for session: AuthenticatedSession) async throws -> Data {
    do {
      return try await client(for: session.credential.serverURL)
        .imageData(path: path, token: session.credential.token)
    } catch {
      _ = await handleUnauthorizedContentError(error)
      throw error
    }
  }

  /// Voltar para um título já aberto não precisa de outra ida ao servidor; o
  /// cache cai inteiro sempre que algo pode ter mudado lá.
  func title(id: Int, for session: AuthenticatedSession, force: Bool = false) async throws
    -> TitleDetail
  {
    if !force, let cached = titleCache[id] { return cached }
    do {
      let detail = try await client(for: session.credential.serverURL)
        .title(id: id, token: session.credential.token)
      titleCache[id] = detail
      return detail
    } catch {
      _ = await handleUnauthorizedContentError(error)
      throw error
    }
  }

  func setFavorite(_ favorite: Bool, titleID: Int, for session: AuthenticatedSession) async throws {
    do {
      _ = try await client(for: session.credential.serverURL)
        .setFavorite(titleID: titleID, favorite: favorite, token: session.credential.token)
      homeState = .idle
      titleCache.removeValue(forKey: titleID)
    } catch {
      _ = await handleUnauthorizedContentError(error)
      throw error
    }
  }

  /// O servidor deriva "assistido" da posição salva — não há rota dedicada para
  /// isso. Marcar leva a posição ao fim; desmarcar a zera.
  func setWatched(_ watched: Bool, file: MediaFileInfo, for session: AuthenticatedSession)
    async throws
  {
    let duration = file.duration > 0 ? file.duration : 1
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL).saveProgress(
        fileID: file.id,
        position: watched ? duration : 0,
        duration: duration,
        token: session.credential.token
      )
    }
    homeState = .idle
    titleCache.removeAll()
  }

  func mediaToken(for session: AuthenticatedSession) async throws -> MediaTokenResponse {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .mediaToken(token: session.credential.token)
    }
  }

  func playbackFile(id: Int, for session: AuthenticatedSession) async throws -> MediaFileInfo {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .file(id: id, token: session.credential.token)
    }
  }

  func mediaTracks(fileID: Int, for session: AuthenticatedSession) async throws -> MediaTracks {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .tracks(fileID: fileID, token: session.credential.token)
    }
  }

  func nextEpisode(fileID: Int, for session: AuthenticatedSession) async throws -> Int? {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .nextEpisode(fileID: fileID, token: session.credential.token).next
    }
  }

  func subtitleText(path: String, for session: AuthenticatedSession) async throws -> String {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .textResource(path: path, token: session.credential.token)
    }
  }

  func playbackPlan(
    fileID: Int, audioTrack: Int? = nil, for session: AuthenticatedSession
  ) async throws -> PlaybackPlan {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .playback(fileID: fileID, audioTrack: audioTrack, token: session.credential.token)
    }
  }

  func prepare(
    fileID: Int, audioTrack: Int? = nil, for session: AuthenticatedSession
  ) async throws -> PreparationProgress {
    try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .prepare(fileID: fileID, audioTrack: audioTrack, token: session.credential.token)
    }
  }

  func saveProgress(
    fileID: Int, position: Double, duration: Double, for session: AuthenticatedSession
  ) async {
    guard position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return }
    do {
      try await client(for: session.credential.serverURL).saveProgress(
        fileID: fileID,
        position: position,
        duration: duration,
        token: session.credential.token
      )
    } catch {
      _ = await handleUnauthorizedContentError(error)
    }
  }

  func approveTV(code: String, for session: AuthenticatedSession) async throws -> String {
    guard let normalized = TVPairingCode.extract(from: code) else {
      throw APIClientError.server(status: 400, message: "O QR Code ou código da TV não é válido.")
    }
    let response = try await authenticatedContentRequest {
      try await client(for: session.credential.serverURL)
        .approveDevice(userCode: normalized, token: session.credential.token)
    }
    return response.deviceName
  }

  func logout() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    errorMessage = nil
    let session = currentSession
    if let session {
      try? await client(for: session.credential.serverURL).logout(token: session.credential.token)
    }
    try? credentialStore.clear()
    resetContent()
    showServerSelection()
    isLoggingOut = false
  }

  /// As artes e as listas pertencem a um servidor e a um token; nada disso pode
  /// sobreviver a uma troca de conta.
  private func resetContent() {
    homeState = .idle
    catalogState = .idle
    loadedCatalogQuery = nil
    isLoadingMoreCatalog = false
    catalogPageError = nil
    titleCache.removeAll()
    Task { await ArtworkCache.shared.clear() }
  }

  var currentSession: AuthenticatedSession? {
    switch phase {
    case .authenticated(let session), .passwordChangeRequired(let session): session
    default: nil
    }
  }

  private func client(for url: URL) -> APIClient {
    APIClient(
      baseURL: url,
      session: sessionFactory(url),
      eventStreamer: eventStreamFactory(url)
    )
  }

  private func handleUnauthorizedContentError(_ error: Error) async -> Bool {
    guard let apiError = error as? APIClientError, apiError.statusCode == 401 else { return false }
    let server = currentSession?.credential.serverURL
    try? credentialStore.clear()
    resetContent()
    signOut(returningTo: server)
    return true
  }

  private func authenticatedContentRequest<Value>(
    _ operation: () async throws -> Value
  ) async throws -> Value {
    do {
      return try await operation()
    } catch {
      _ = await handleUnauthorizedContentError(error)
      throw error
    }
  }

  private static func parseDate(_ value: String) -> Date? {
    ISO8601.date(from: value)
  }
}

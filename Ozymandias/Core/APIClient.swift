import Foundation

protocol HTTPSession: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

enum APIClientError: LocalizedError, Sendable {
  case invalidResponse
  case invalidPayload
  case server(status: Int, message: String)
  case transport(message: String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "O servidor enviou uma resposta inválida."
    case .invalidPayload:
      "O servidor enviou dados que o app não reconhece."
    case .server(_, let message):
      message
    case .transport(let message):
      message
    }
  }

  var statusCode: Int? {
    if case .server(let status, _) = self { return status }
    return nil
  }
}

struct APIClient: Sendable {
  /// Chamadas atendidas pelo banco local do servidor.
  static let defaultTimeout: TimeInterval = 8
  /// Chamadas em que o servidor conversa com o TMDB ou dispara trabalho pesado.
  static let slowTimeout: TimeInterval = 30

  let baseURL: URL
  let session: any HTTPSession
  let eventStreamer: any EventStreaming

  init(
    baseURL: URL,
    session: any HTTPSession = URLSession.shared,
    eventStreamer: any EventStreaming = URLSessionEventStreamer()
  ) {
    self.baseURL = baseURL
    self.session = session
    self.eventStreamer = eventStreamer
  }

  func health() async throws -> HealthResponse {
    let response: HealthResponse = try await send(path: "/healthz")
    guard response.status == "ok" else { throw APIClientError.invalidPayload }
    return response
  }

  func login(username: String, password: String, remember: Bool) async throws -> UserResponse {
    let body = LoginRequest(
      username: username,
      password: password,
      remember: remember,
      tokenNaResposta: true
    )
    let response: UserResponse = try await send(path: "/api/auth/login", method: "POST", body: body)
    guard response.token?.isEmpty == false, response.expiraEm?.isEmpty == false else {
      throw APIClientError.invalidPayload
    }
    return response
  }

  func me(token: String) async throws -> UserResponse {
    try await send(path: "/api/auth/me", bearer: token)
  }

  func logout(token: String) async throws {
    let _: LogoutResponse = try await send(path: "/api/auth/logout", method: "POST", bearer: token)
  }

  func home(token: String) async throws -> HomeResponse {
    try await send(path: "/api/home", bearer: token)
  }

  func artists(token: String) async throws -> [ArtistCard] {
    try await send(path: "/api/artistas", bearer: token)
  }

  func artist(name: String, token: String) async throws -> ArtistDetail {
    try await send(path: artistPath(name), bearer: token)
  }

  func libraries(token: String) async throws -> [MediaLibrary] {
    try await send(path: "/api/libraries", bearer: token)
  }

  func titles(query: CatalogQuery = CatalogQuery(), token: String) async throws -> TitlesResponse {
    try await send(path: titlesPath(query), bearer: token)
  }

  func title(id: Int, token: String) async throws -> TitleDetail {
    try await send(path: "/api/titles/\(id)", bearer: token)
  }

  func setFavorite(titleID: Int, favorite: Bool, token: String) async throws -> FavoriteResponse {
    try await send(
      path: "/api/favorites/\(titleID)",
      method: favorite ? "POST" : "DELETE",
      bearer: token
    )
  }

  func collections(token: String) async throws -> [MediaCollection] {
    try await send(path: "/api/colecoes", bearer: token)
  }

  func collection(id: Int, token: String) async throws -> CollectionContent {
    try await send(path: "/api/colecoes/\(id)", bearer: token)
  }

  func createCollection(name: String, token: String) async throws -> MediaCollection {
    try await send(
      path: "/api/colecoes", method: "POST", bearer: token,
      body: CollectionNameRequest(name: name)
    )
  }

  func renameCollection(id: Int, name: String, token: String) async throws {
    let _: OperationResponse = try await send(
      path: "/api/colecoes/\(id)", method: "PUT", bearer: token,
      body: CollectionNameRequest(name: name)
    )
  }

  func deleteCollection(id: Int, token: String) async throws {
    let _: OperationResponse = try await send(
      path: "/api/colecoes/\(id)", method: "DELETE", bearer: token)
  }

  func setCollectionMembership(
    collectionID: Int, titleID: Int, included: Bool, token: String
  ) async throws {
    let _: OperationResponse = try await send(
      path: "/api/colecoes/\(collectionID)/itens/\(titleID)",
      method: included ? "POST" : "DELETE",
      bearer: token
    )
  }

  func collectionIDs(titleID: Int, token: String) async throws -> [Int] {
    let response: TitleCollectionsResponse = try await send(
      path: "/api/titles/\(titleID)/colecoes", bearer: token)
    return response.collectionIDs
  }

  func scanStatus(token: String) async throws -> ScanStatus {
    try await send(path: "/api/scan/status", bearer: token)
  }

  func startScan(token: String) async throws -> StartedResponse {
    try await send(path: "/api/scan", method: "POST", bearer: token, timeout: Self.slowTimeout)
  }

  func refreshMetadata(all: Bool, token: String) async throws -> StartedResponse {
    try await send(
      path: all ? "/api/metadata?all=1" : "/api/metadata",
      method: "POST",
      bearer: token,
      timeout: Self.slowTimeout
    )
  }

  func metrics(token: String) async throws -> MetricsSnapshot {
    try await send(path: "/api/metrics/status", bearer: token)
  }

  func scanEvents(token: String) throws -> AsyncThrowingStream<ScanStatus, Error> {
    try eventStream(path: "/api/scan/events", bearer: token)
  }

  func metricEvents(token: String) throws -> AsyncThrowingStream<MetricsSnapshot, Error> {
    try eventStream(path: "/api/metrics/events", bearer: token)
  }

  func settings(token: String) async throws -> ServerSettings {
    try await send(path: "/api/settings", bearer: token)
  }

  func updateSettings(_ request: SettingsUpdateRequest, token: String) async throws
    -> ServerSettings
  {
    try await send(
      path: "/api/settings", method: "PUT", bearer: token, body: request,
      timeout: Self.slowTimeout)
  }

  func matchCandidates(titleID: Int, query: String, year: Int?, token: String) async throws
    -> [MatchCandidate]
  {
    let response: MatchResultsResponse = try await send(
      path: matchPath(titleID: titleID, query: query, year: year), bearer: token,
      timeout: Self.slowTimeout)
    return response.results
  }

  func applyMatch(titleID: Int, tmdbID: Int, token: String) async throws {
    let _: OperationResponse = try await send(
      path: "/api/titles/\(titleID)/match", method: "POST", bearer: token,
      body: MatchRequest(tmdbID: tmdbID),
      timeout: Self.slowTimeout
    )
  }

  func mediaToken(token: String) async throws -> MediaTokenResponse {
    try await send(path: "/api/auth/media-token", method: "POST", bearer: token)
  }

  func file(id: Int, token: String) async throws -> MediaFileInfo {
    try await send(path: "/api/files/\(id)", bearer: token)
  }

  func tracks(fileID: Int, token: String) async throws -> MediaTracks {
    try await send(path: "/api/files/\(fileID)/faixas", bearer: token)
  }

  func nextEpisode(fileID: Int, token: String) async throws -> NextEpisodeResponse {
    try await send(path: "/api/files/\(fileID)/next", bearer: token)
  }

  func playback(fileID: Int, audioTrack: Int? = nil, token: String) async throws -> PlaybackPlan {
    try await send(path: playbackPath(fileID: fileID, audioTrack: audioTrack), bearer: token)
  }

  func prepare(fileID: Int, audioTrack: Int? = nil, token: String) async throws
    -> PreparationProgress
  {
    try await send(
      path: preparePath(fileID: fileID, audioTrack: audioTrack), method: "POST", bearer: token)
  }

  func textResource(path: String, token: String) async throws -> String {
    let data = try await resourceData(path: path, token: token)
    guard let text = String(data: data, encoding: .utf8) else {
      throw APIClientError.invalidPayload
    }
    return text
  }

  func saveProgress(fileID: Int, position: Double, duration: Double, token: String) async throws {
    try await sendWithoutResponse(
      path: "/api/progress/\(fileID)",
      method: "PUT",
      bearer: token,
      body: ProgressRequest(position: position, duration: duration)
    )
  }

  func imageData(path: String, token: String) async throws -> Data {
    try await resourceData(path: path, token: token)
  }

  private func resourceData(path: String, token: String) async throws -> Data {
    let url = try makeURL(path: path)
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let data: Data
    let response: URLResponse
    (data, response) = try await perform(request, retryingTransientFailures: true)
    guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw APIClientError.server(
        status: http.statusCode, message: "Não foi possível carregar o conteúdo.")
    }
    return data
  }

  private func eventStream<Response: Decodable & Sendable>(
    path: String, bearer: String
  ) throws -> AsyncThrowingStream<Response, Error> {
    let url = try makeURL(path: path)
    var request = URLRequest(url: url, timeoutInterval: 60)
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    let source = eventStreamer.events(for: request)

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await data in source {
            try Task.checkCancellation()
            do {
              continuation.yield(try JSONDecoder().decode(Response.self, from: data))
            } catch {
              throw APIClientError.invalidPayload
            }
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func send<Response: Decodable>(
    path: String,
    method: String = "GET",
    bearer: String? = nil,
    timeout: TimeInterval = APIClient.defaultTimeout
  ) async throws -> Response {
    try await send(
      path: path, method: method, bearer: bearer, body: Optional<EmptyBody>.none, timeout: timeout)
  }

  private func send<Response: Decodable, Body: Encodable>(
    path: String,
    method: String = "GET",
    bearer: String? = nil,
    body: Body?,
    timeout: TimeInterval = APIClient.defaultTimeout
  ) async throws -> Response {
    let url = try makeURL(path: path)
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let bearer {
      request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpBody = try JSONEncoder().encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let data: Data
    let response: URLResponse
    (data, response) = try await perform(
      request,
      retryingTransientFailures: method == "GET"
    )
    guard let http = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error)
        ?? "Erro \(http.statusCode) ao falar com o servidor."
      throw APIClientError.server(status: http.statusCode, message: message)
    }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw APIClientError.invalidPayload
    }
  }

  private func sendWithoutResponse<Body: Encodable>(
    path: String,
    method: String,
    bearer: String,
    body: Body
  ) async throws {
    let url = try makeURL(path: path)
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let data: Data
    let response: URLResponse
    (data, response) = try await perform(request, retryingTransientFailures: false)
    guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error)
        ?? "Erro \(http.statusCode) ao falar com o servidor."
      throw APIClientError.server(status: http.statusCode, message: message)
    }
  }

  private func makeURL(path: String) throws -> URL {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
      throw APIClientError.invalidResponse
    }
    return url
  }

  /// Ao voltar do background, o pool do URLSession pode tentar reutilizar uma
  /// conexão que a troca de rede já encerrou. Uma segunda tentativa de leitura
  /// abre uma conexão nova e evita mostrar um erro que desapareceria ao tocar
  /// em "Tentar novamente". Escritas nunca passam por este caminho de retry.
  private func perform(
    _ request: URLRequest,
    retryingTransientFailures: Bool
  ) async throws -> (Data, URLResponse) {
    let maximumAttempts = retryingTransientFailures ? 2 : 1
    var attempt = 1

    while true {
      do {
        return try await session.data(for: request)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard attempt < maximumAttempts, Self.isTransientTransportError(error) else {
          throw APIClientError.transport(message: Self.transportMessage(for: error))
        }
        attempt += 1
        try await Task.sleep(for: .milliseconds(250))
      }
    }
  }

  private func playbackPath(fileID: Int, audioTrack: Int?) -> String {
    capabilityPath(fileID: fileID, action: "playback", audioTrack: audioTrack)
  }

  private func preparePath(fileID: Int, audioTrack: Int?) -> String {
    capabilityPath(fileID: fileID, action: "prepare", audioTrack: audioTrack)
  }

  private func capabilityPath(fileID: Int, action: String, audioTrack: Int?) -> String {
    var path =
      "/api/files/\(fileID)/\(action)?vid=h264,hevc&aud=aac,ac3,eac3,mp3,alac,flac&cont=mp4,mov,m4v,m4a"
    if let audioTrack { path += "&audio=\(audioTrack)" }
    return path
  }

  private func titlesPath(_ query: CatalogQuery) -> String {
    var components = URLComponents()
    components.path = "/api/titles"
    var items: [URLQueryItem] = []
    if let libraryID = query.libraryID {
      items.append(URLQueryItem(name: "library", value: String(libraryID)))
    }
    if let kind = query.kind {
      items.append(URLQueryItem(name: "kind", value: kind.rawValue))
    }
    let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { items.append(URLQueryItem(name: "q", value: text)) }
    items.append(URLQueryItem(name: "sort", value: query.sort.rawValue))
    items.append(URLQueryItem(name: "limit", value: String(query.limit)))
    if query.offset > 0 { items.append(URLQueryItem(name: "offset", value: String(query.offset))) }
    components.queryItems = items
    return components.string ?? "/api/titles"
  }

  private func matchPath(titleID: Int, query: String, year: Int?) -> String {
    var components = URLComponents()
    components.path = "/api/titles/\(titleID)/matches"
    var items = [URLQueryItem(name: "q", value: query)]
    if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
    components.queryItems = items
    return components.string ?? "/api/titles/\(titleID)/matches"
  }

  private func artistPath(_ name: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    return "/api/artistas/\(encoded)"
  }

  private static func transportMessage(for error: Error) -> String {
    guard let urlError = error as? URLError else {
      return "Não foi possível falar com o servidor."
    }
    switch urlError.code {
    case .timedOut:
      return "O servidor demorou demais para responder."
    case .notConnectedToInternet, .networkConnectionLost:
      return "Sem conexão com a rede."
    case .cannotConnectToHost, .cannotFindHost:
      return "Não encontrei o servidor nesse endereço."
    default:
      return "Não foi possível falar com o servidor."
    }
  }

  private static func isTransientTransportError(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
      .cannotFindHost, .dnsLookupFailed, .resourceUnavailable:
      return true
    default:
      return false
    }
  }
}

private struct EmptyBody: Encodable {}

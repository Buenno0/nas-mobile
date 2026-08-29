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
  let baseURL: URL
  let session: any HTTPSession

  init(baseURL: URL, session: any HTTPSession = URLSession.shared) {
    self.baseURL = baseURL
    self.session = session
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

  private func send<Response: Decodable>(
    path: String,
    method: String = "GET",
    bearer: String? = nil
  ) async throws -> Response {
    try await send(path: path, method: method, bearer: bearer, body: Optional<EmptyBody>.none)
  }

  private func send<Response: Decodable, Body: Encodable>(
    path: String,
    method: String = "GET",
    bearer: String? = nil,
    body: Body?
  ) async throws -> Response {
    let url = baseURL.appending(path: path)
    var request = URLRequest(url: url, timeoutInterval: 8)
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
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw APIClientError.transport(message: Self.transportMessage(for: error))
    }
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
}

private struct EmptyBody: Encodable {}

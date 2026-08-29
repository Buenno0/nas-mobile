import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
  let status: String
  let time: String
}

struct LoginRequest: Codable, Equatable, Sendable {
  let username: String
  let password: String
  let remember: Bool
  let tokenNaResposta: Bool

  enum CodingKeys: String, CodingKey {
    case username, password, remember
    case tokenNaResposta = "token_na_resposta"
  }
}

struct UserResponse: Codable, Equatable, Sendable {
  let username: String
  let mustChangePassword: Bool
  let isAdmin: Bool
  let token: String?
  let expiraEm: String?

  enum CodingKeys: String, CodingKey {
    case username, token
    case mustChangePassword = "must_change_password"
    case isAdmin = "is_admin"
    case expiraEm = "expira_em"
  }
}

struct APIErrorResponse: Codable, Equatable, Sendable {
  let error: String
}

struct LogoutResponse: Codable, Equatable, Sendable {
  let ok: Bool
}

struct SessionCredential: Codable, Equatable, Sendable {
  let serverURL: URL
  let token: String
  let expiresAt: Date
}

struct AuthenticatedSession: Equatable, Sendable {
  let user: UserResponse
  let credential: SessionCredential
}

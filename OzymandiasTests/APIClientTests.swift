import Foundation
import Testing

@testable import Ozymandias

struct APIClientTests {
  private let baseURL = URL(string: "http://localhost:8787")!

  @Test func validatesHealthyServer() async throws {
    let session = MockHTTPSession { request in
      #expect(request.url?.path == "/healthz")
      return Self.response(
        for: request, status: 200, json: #"{"status":"ok","time":"2026-08-28T12:00:00Z"}"#)
    }
    let health = try await APIClient(baseURL: baseURL, session: session).health()
    #expect(health.status == "ok")
  }

  @Test func rejectsUnexpectedHealthPayload() async {
    let session = MockHTTPSession { request in
      Self.response(for: request, status: 200, json: #"{"status":"starting","time":"now"}"#)
    }
    await #expect(throws: APIClientError.self) {
      try await APIClient(baseURL: baseURL, session: session).health()
    }
  }

  @Test func loginSendsNativeClientContract() async throws {
    let recorder = RequestRecorder()
    let session = MockHTTPSession { request in
      await recorder.record(request)
      return Self.response(
        for: request,
        status: 200,
        json:
          #"{"username":"ana","must_change_password":false,"is_admin":true,"token":"secret","expira_em":"2099-08-28T12:00:00Z"}"#
      )
    }
    let user = try await APIClient(baseURL: baseURL, session: session)
      .login(username: "ana", password: "password", remember: true)
    #expect(user.username == "ana")
    let request = await recorder.request
    #expect(request?.httpMethod == "POST")
    let body = try #require(request?.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["token_na_resposta"] as? Bool == true)
    #expect(json["remember"] as? Bool == true)
  }

  @Test func preservesServerErrorMessageAndStatus() async {
    let session = MockHTTPSession { request in
      Self.response(for: request, status: 401, json: #"{"error":"usuário ou senha incorretos"}"#)
    }
    do {
      _ = try await APIClient(baseURL: baseURL, session: session)
        .login(username: "x", password: "y", remember: false)
      Issue.record("O login deveria falhar")
    } catch let error as APIClientError {
      #expect(error.statusCode == 401)
      #expect(error.localizedDescription == "usuário ou senha incorretos")
    } catch {
      Issue.record("Erro inesperado: \(error)")
    }
  }

  @Test func mapsTimeoutToFriendlyMessage() async {
    let session = MockHTTPSession { _ in throw URLError(.timedOut) }
    await #expect(throws: APIClientError.self) {
      try await APIClient(baseURL: baseURL, session: session).health()
    }
  }

  static func response(for request: URLRequest, status: Int, json: String) -> (Data, URLResponse) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(json.utf8), response)
  }
}

struct MockHTTPSession: HTTPSession {
  let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
    self.handler = handler
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await handler(request)
  }
}

private actor RequestRecorder {
  private(set) var request: URLRequest?
  func record(_ request: URLRequest) { self.request = request }
}

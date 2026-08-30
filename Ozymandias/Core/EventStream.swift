import Foundation

protocol EventStreaming: Sendable {
  func events(for request: URLRequest) -> AsyncThrowingStream<Data, Error>
}

struct URLSessionEventStreamer: EventStreaming {
  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func events(for request: URLRequest) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let (bytes, response) = try await session.bytes(for: request)
          guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
          }
          guard (200..<300).contains(http.statusCode) else {
            throw APIClientError.server(
              status: http.statusCode,
              message: "Erro \(http.statusCode) ao conectar às atualizações do servidor."
            )
          }
          guard
            http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
              .hasPrefix("text/event-stream") == true
          else {
            throw APIClientError.invalidResponse
          }

          var parser = ServerSentEventParser()
          for try await line in bytes.lines {
            try Task.checkCancellation()
            if let event = parser.consume(line) { continuation.yield(event) }
          }
          if let event = parser.finish() { continuation.yield(event) }
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
}

struct ServerSentEventParser: Sendable {
  private var dataLines: [String] = []

  mutating func consume(_ line: String) -> Data? {
    if line.isEmpty { return finish() }
    guard line.hasPrefix("data:") else { return nil }
    var value = String(line.dropFirst(5))
    if value.first == " " { value.removeFirst() }
    dataLines.append(value)
    return nil
  }

  mutating func finish() -> Data? {
    guard !dataLines.isEmpty else { return nil }
    defer { dataLines.removeAll(keepingCapacity: true) }
    return Data(dataLines.joined(separator: "\n").utf8)
  }
}

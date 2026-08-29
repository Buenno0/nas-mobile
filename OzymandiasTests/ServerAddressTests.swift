import Foundation
import Testing

@testable import Ozymandias

struct ServerAddressTests {
  @Test func addsHTTPWhenSchemeIsMissing() throws {
    #expect(try ServerAddress.normalize("localhost:8787").absoluteString == "http://localhost:8787")
  }

  @Test func trimsWhitespaceAndTrailingSlash() throws {
    #expect(
      try ServerAddress.normalize("  https://nas.local/  ").absoluteString == "https://nas.local")
  }

  @Test func acceptsLANAddressWithPort() throws {
    #expect(try ServerAddress.normalize("http://192.168.1.20:8787").host == "192.168.1.20")
  }

  @Test func rejectsUnsupportedSchemeAndPath() {
    #expect(throws: ServerAddressError.unsupportedScheme) {
      try ServerAddress.normalize("ftp://nas.local")
    }
    #expect(throws: ServerAddressError.invalid) {
      try ServerAddress.normalize("https://nas.local/subpath")
    }
  }
}

struct ServerHistoryTests {
  @Test func keepsOnlyTheThreeMostRecentUniqueServers() throws {
    let suite = "ServerHistoryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let history = ServerHistory(defaults: defaults)

    for port in 8787...8790 {
      history.remember(URL(string: "http://localhost:\(port)")!)
    }
    history.remember(URL(string: "http://localhost:8789")!)

    #expect(
      history.load() == [
        "http://localhost:8789", "http://localhost:8790", "http://localhost:8788",
      ])
  }
}

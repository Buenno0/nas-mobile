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

  @Test func acceptsPrivateAndLinkLocalLiterals() throws {
    for address in ["http://10.0.0.4:8787", "http://172.20.5.1", "http://127.0.0.1:8787", "http://[fd00::1]"] {
      #expect(throws: Never.self) { try ServerAddress.normalize(address) }
    }
  }

  // A mesma regra que o cliente Fire TV aplica: fora da rede local, só HTTPS.
  // Antes, quem recusava era o App Transport Security em runtime, e o usuário
  // via "Não foi possível falar com o servidor" sem saber o que corrigir.
  @Test func requiresHTTPSOutsideTheLocalNetwork() {
    for address in ["http://ozymandias.exemplo.com", "http://203.0.113.10:8787", "nas.exemplo.com"] {
      #expect(throws: ServerAddressError.insecurePublicHost) {
        try ServerAddress.normalize(address)
      }
    }
  }

  @Test func acceptsPublicHostOverHTTPS() throws {
    #expect(
      try ServerAddress.normalize("https://ozymandias.exemplo.com").host == "ozymandias.exemplo.com")
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

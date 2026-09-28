import Foundation
import Network
import Observation

struct DiscoveredServer: Identifiable, Equatable, Sendable {
  let name: String
  let address: String

  var id: String { address }
}

/// Procura o servidor na rede local pelo mesmo serviço que o cliente Fire TV já
/// usava (`_ozymandias._tcp`). É puro atalho: nada aqui é obrigatório para
/// conectar, e quando a busca não acha nada — ou o usuário nega o acesso à rede
/// local — a tela de servidores fica exatamente como era, só com o campo manual
/// e os recentes.
@MainActor
@Observable
final class ServerDiscovery {
  static let serviceType = "_ozymandias._tcp"

  private(set) var servers: [DiscoveredServer] = []

  private var browser: NWBrowser?
  private var resolvers: [String: NWConnection] = [:]

  func start() {
    guard browser == nil else { return }
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = false

    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let endpoints = results.map(\.endpoint)
      Task { @MainActor in self?.handle(endpoints) }
    }
    browser.stateUpdateHandler = { [weak self] state in
      guard case .failed = state else { return }
      Task { @MainActor in self?.stop() }
    }
    self.browser = browser
    browser.start(queue: .main)
  }

  func stop() {
    browser?.cancel()
    browser = nil
    for resolver in resolvers.values { resolver.cancel() }
    resolvers.removeAll()
  }

  /// O Bonjour entrega um endpoint de serviço, não um endereço. Resolver exige
  /// abrir uma conexão e ler o caminho dela — é o preço de não usar a API
  /// obsoleta de `NetService`.
  private func handle(_ endpoints: [NWEndpoint]) {
    let names = Set(endpoints.compactMap(Self.serviceName))
    servers.removeAll { !names.contains($0.name) }

    for endpoint in endpoints {
      guard let name = Self.serviceName(endpoint),
        resolvers[name] == nil,
        !servers.contains(where: { $0.name == name })
      else { continue }
      resolve(endpoint, name: name)
    }
  }

  private func resolve(_ endpoint: NWEndpoint, name: String) {
    let connection = NWConnection(to: endpoint, using: .tcp)
    resolvers[name] = connection
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        let remote = connection.currentPath?.remoteEndpoint
        Task { @MainActor in
          self?.finishResolving(name)
          guard let address = Self.address(for: remote) else { return }
          self?.add(DiscoveredServer(name: name, address: address))
        }
      case .failed, .cancelled:
        Task { @MainActor in self?.finishResolving(name) }
      default:
        break
      }
    }
    connection.start(queue: .main)
  }

  private func finishResolving(_ name: String) {
    resolvers[name]?.cancel()
    resolvers.removeValue(forKey: name)
  }

  private func add(_ server: DiscoveredServer) {
    guard !servers.contains(where: { $0.address == server.address }) else { return }
    servers.append(server)
    servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  nonisolated private static func serviceName(_ endpoint: NWEndpoint) -> String? {
    guard case .service(let name, _, _, _) = endpoint else { return nil }
    return name
  }

  nonisolated private static func address(for endpoint: NWEndpoint?) -> String? {
    guard case .hostPort(let host, let port) = endpoint else { return nil }
    let text =
      switch host {
      case .name(let name, _): name
      case .ipv4(let address): "\(address)"
      case .ipv6(let address): "\(address)"
      @unknown default: ""
      }
    return serverAddress(host: text, port: port.rawValue)
  }

  /// Endereço IPv6 precisa de colchetes na URL, e tanto nomes quanto IPs chegam
  /// com sufixo de interface (`%en0`) e com o ponto final do DNS.
  nonisolated static func serverAddress(host rawHost: String, port: UInt16) -> String? {
    var host = rawHost.split(separator: "%").first.map(String.init) ?? rawHost
    while host.hasSuffix(".") { host.removeLast() }
    guard !host.isEmpty, port > 0 else { return nil }
    if host.contains(":") { host = "[\(host)]" }
    return "http://\(host):\(port)"
  }
}

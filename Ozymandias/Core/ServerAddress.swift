import Foundation

enum ServerAddressError: LocalizedError, Equatable {
  case empty
  case invalid
  case unsupportedScheme
  case insecurePublicHost

  var errorDescription: String? {
    switch self {
    case .empty: "Informe o endereço do servidor."
    case .invalid: "O endereço do servidor não é válido."
    case .unsupportedScheme: "Use um endereço começando com http:// ou https://."
    case .insecurePublicHost: "Endereços fora da sua rede precisam usar https://."
    }
  }
}

enum ServerAddress {
  static let defaultValue = "http://localhost:8787"

  static func normalize(_ input: String) throws -> URL {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw ServerAddressError.empty }

    if !value.contains("://") {
      value = "http://" + value
    }

    guard var components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(),
      let host = components.host,
      !host.isEmpty
    else {
      throw ServerAddressError.invalid
    }
    guard scheme == "http" || scheme == "https" else {
      throw ServerAddressError.unsupportedScheme
    }
    guard components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil
    else {
      throw ServerAddressError.invalid
    }

    // O Android já recusava HTTP para host público com esta mensagem; aqui quem
    // barrava era o App Transport Security, em runtime, com um erro de transporte
    // genérico. A regra passa a ser a mesma nos dois clientes, e o texto explica
    // o que fazer. O conjunto aceito é o mesmo que `NSAllowsLocalNetworking`
    // permite de fato, então o app não promete uma conexão que o sistema recusa.
    guard scheme == "https" || isLocalHost(host) else {
      throw ServerAddressError.insecurePublicHost
    }

    components.scheme = scheme
    components.path = components.path == "/" ? "" : components.path
    guard components.path.isEmpty, let url = components.url else {
      throw ServerAddressError.invalid
    }
    return url
  }

  /// Nomes e literais que o ATS trata como rede local. Hostnames comuns ficam de
  /// fora de propósito: resolver DNS aqui tornaria a validação assíncrona, e o
  /// ATS os bloquearia de todo jeito.
  private static func isLocalHost(_ host: String) -> Bool {
    let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if value == "localhost" || value == "::1" { return true }
    if value.hasSuffix(".local") || value.hasSuffix(".home.arpa") { return true }
    if let octets = ipv4Octets(value) { return isPrivateIPv4(octets) }
    // IPv6 único-local (fc00::/7) e link-local (fe80::/10).
    if value.hasPrefix("fc") || value.hasPrefix("fd") || value.hasPrefix("fe8")
      || value.hasPrefix("fe9") || value.hasPrefix("fea") || value.hasPrefix("feb")
    {
      return value.contains(":")
    }
    return false
  }

  private static func ipv4Octets(_ value: String) -> [Int]? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    let octets = parts.compactMap { Int($0) }
    guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
    return octets
  }

  private static func isPrivateIPv4(_ octets: [Int]) -> Bool {
    switch (octets[0], octets[1]) {
    case (10, _), (127, _), (192, 168): true
    case (172, 16...31): true
    case (169, 254): true
    default: false
    }
  }
}

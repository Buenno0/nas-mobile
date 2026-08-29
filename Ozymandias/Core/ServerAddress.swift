import Foundation

enum ServerAddressError: LocalizedError, Equatable {
  case empty
  case invalid
  case unsupportedScheme

  var errorDescription: String? {
    switch self {
    case .empty: "Informe o endereço do servidor."
    case .invalid: "O endereço do servidor não é válido."
    case .unsupportedScheme: "Use um endereço começando com http:// ou https://."
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

    components.scheme = scheme
    components.path = components.path == "/" ? "" : components.path
    guard components.path.isEmpty, let url = components.url else {
      throw ServerAddressError.invalid
    }
    return url
  }
}

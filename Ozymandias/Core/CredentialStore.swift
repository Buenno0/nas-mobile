import Foundation
import Security

protocol CredentialStoring: Sendable {
  func load() throws -> SessionCredential?
  func save(_ credential: SessionCredential) throws
  func clear() throws
}

enum CredentialStoreError: LocalizedError {
  case encoding
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encoding: "Não foi possível preparar a sessão para armazenamento."
    case .keychain(let status): "O Keychain recusou a operação (\(status))."
    }
  }
}

struct KeychainCredentialStore: CredentialStoring {
  private let service = "com.buenno.Ozymandias.session"
  private let account = "current"

  func load() throws -> SessionCredential? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw CredentialStoreError.keychain(status)
    }
    guard let credential = try? JSONDecoder().decode(SessionCredential.self, from: data) else {
      throw CredentialStoreError.encoding
    }
    return credential
  }

  func save(_ credential: SessionCredential) throws {
    guard let data = try? JSONEncoder().encode(credential) else {
      throw CredentialStoreError.encoding
    }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var query = baseQuery
      for (key, value) in attributes {
        query[key] = value
      }
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
    } else if status != errSecSuccess {
      throw CredentialStoreError.keychain(status)
    }
  }

  func clear() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

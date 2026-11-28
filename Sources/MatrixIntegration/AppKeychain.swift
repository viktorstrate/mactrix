import Foundation
import Security

enum KeychainError: Error {
  case unexpectedStatus(OSStatus)
}

/// Key-value storage for secrets. Abstracted so account storage can be tested without the system keychain.
protocol KeychainStore: Sendable {
  func save(_ data: Data, forKey key: String) throws
  func load(forKey key: String) throws -> Data?
  func delete(forKey key: String) throws
  func keys(withPrefix prefix: String) throws -> [String]
}

struct AppKeychain: KeychainStore {
  private let service: String

  init(service: String = Bundle.main.bundleIdentifier!) {
    self.service = service
  }

  private var baseQuery: [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      /// change to true for Data Protection keychain mode
      kSecUseDataProtectionKeychain: false,
    ]
  }

  /// Saves data for the given key, creating or updating the keychain item.
  func save(_ data: Data, forKey key: String) throws {
    var query = baseQuery
    query[kSecAttrAccount] = key

    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if updateStatus == errSecItemNotFound {
      query[kSecValueData] = data
      query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus)
      }
    } else if updateStatus != errSecSuccess {
      /// with kSecUseDataProtectionKeychain set to true, this will throw with error -34018, which according to
      /// https://github.com/apple-oss-distributions/Security/blob/09becc8fb155462f0853f99cd09c26b10a38e2f4/sec/Security/SecBasePriv.h#L113
      /// is the error "Internal error when a required entitlement isn't present"
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }

  /// Returns the data stored for the given key, or `nil` if no item exists.
  func load(forKey key: String) throws -> Data? {
    var query = baseQuery
    query[kSecAttrAccount] = key
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne

    var result: AnyObject?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
    return result as? Data
  }

  /// Removes the item stored for the given key. Succeeds if no item exists.
  func delete(forKey key: String) throws {
    var query = baseQuery
    query[kSecAttrAccount] = key
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Returns the keys of all items in this service starting with `prefix`.
  func keys(withPrefix prefix: String) throws -> [String] {
    var query = baseQuery
    query[kSecReturnAttributes] = true
    query[kSecMatchLimit] = kSecMatchLimitAll

    var result: AnyObject?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
    let items = result as? [[CFString: Any]] ?? []
    return items.compactMap { $0[kSecAttrAccount] as? String }.filter { $0.hasPrefix(prefix) }
  }
}

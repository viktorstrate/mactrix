import Foundation
import OSLog

/// Persists the sessions of all signed-in accounts.
///
/// Each account is identified by its `storeID`, which also names its SQLite store directories.
/// Secrets live in one keychain item per account (`session.<storeID>`); the keychain is the
/// source of truth for which accounts exist. Non-secret metadata (display order, active account)
/// lives in `UserDefaults`.
public struct AccountStore: Sendable {
  static let legacySessionKey = "UserSession"
  static let sessionKeyPrefix = "session."
  static let currentSchemaVersion = 1

  enum DefaultsKey {
    static let order = "accounts.order"
    // Named before each window had its own account; kept so the stored value carries over.
    static let lastFocused = "accounts.active"
    static let schemaVersion = "accounts.schemaVersion"
  }

  private let keychain: any KeychainStore
  nonisolated(unsafe) private let defaults: UserDefaults

  public init() {
    self.init(keychain: AppKeychain(), defaults: .standard)
  }

  init(keychain: any KeychainStore, defaults: UserDefaults) {
    self.keychain = keychain
    self.defaults = defaults
  }

  static func sessionKey(for storeID: String) -> String {
    sessionKeyPrefix + storeID
  }

  // MARK: Sessions

  /// Returns all stored sessions in display order. Unreadable items are skipped.
  func loadAll() throws -> [UserSession] {
    var sessions: [String: UserSession] = [:]
    for storeID in try allStoreIDs() {
      do {
        if let session = try load(storeID: storeID) {
          sessions[storeID] = session
        }
      } catch {
        Logger.matrixClient.error("Skipping unreadable session \(storeID): \(error)")
      }
    }

    let order = orderedStoreIDs(existing: Set(sessions.keys))
    return order.compactMap { sessions[$0] }
  }

  /// The store IDs of every stored session, including ones that can't be decoded.
  func allStoreIDs() throws -> Set<String> {
    Set(
      try keychain.keys(withPrefix: Self.sessionKeyPrefix)
        .map { String($0.dropFirst(Self.sessionKeyPrefix.count)) })
  }

  /// Whether a session from before per-account storage is still present.
  func hasLegacySession() throws -> Bool {
    try keychain.load(forKey: Self.legacySessionKey) != nil
  }

  func load(storeID: String) throws -> UserSession? {
    guard let data = try keychain.load(forKey: Self.sessionKey(for: storeID)) else { return nil }
    return try JSONDecoder().decode(UserSession.self, from: data)
  }

  /// Creates or updates the session for `session.storeID`, appending new accounts to the order.
  func save(_ session: UserSession) throws {
    let data = try JSONEncoder().encode(session)
    try keychain.save(data, forKey: Self.sessionKey(for: session.storeID))

    var order = storedOrder
    if !order.contains(session.storeID) {
      order.append(session.storeID)
      defaults.set(order, forKey: DefaultsKey.order)
    }
  }

  /// Removes the account's session and metadata. Other accounts are untouched.
  func remove(storeID: String) throws {
    try keychain.delete(forKey: Self.sessionKey(for: storeID))
    defaults.set(storedOrder.filter { $0 != storeID }, forKey: DefaultsKey.order)
    if lastFocusedStoreID == storeID {
      lastFocusedStoreID = nil
    }
  }

  // MARK: Metadata

  /// The account of the most recently focused window, if it still exists. New windows open on it.
  public var lastFocusedStoreID: String? {
    get { defaults.string(forKey: DefaultsKey.lastFocused) }
    nonmutating set { defaults.set(newValue, forKey: DefaultsKey.lastFocused) }
  }

  /// Persists the display order of accounts.
  public func setOrder(_ storeIDs: [String]) {
    defaults.set(storeIDs, forKey: DefaultsKey.order)
  }

  private var storedOrder: [String] {
    defaults.stringArray(forKey: DefaultsKey.order) ?? []
  }

  /// Orders `existing` by the stored order, appending unknown IDs (sorted, for stability), and
  /// prunes stored IDs that no longer have a session.
  private func orderedStoreIDs(existing: Set<String>) -> [String] {
    let stored = storedOrder
    var order = stored.filter { existing.contains($0) }
    order += existing.subtracting(order).sorted()
    if order != stored {
      defaults.set(order, forKey: DefaultsKey.order)
    }
    return order
  }

  // MARK: Migration

  /// Moves a session stored by earlier versions under the single `UserSession` key to the
  /// per-account format.
  ///
  /// Safe to run on every launch and to interrupt at any point: the new item is written and
  /// verified before the legacy item is removed, and an unreadable legacy item is never removed.
  func migrateLegacyIfNeeded() throws {
    if defaults.integer(forKey: DefaultsKey.schemaVersion) >= Self.currentSchemaVersion {
      // A previous migration may have been interrupted before removing the legacy item.
      removeLegacySession()
      return
    }

    guard let legacyData = try keychain.load(forKey: Self.legacySessionKey) else {
      defaults.set(Self.currentSchemaVersion, forKey: DefaultsKey.schemaVersion)
      return
    }

    let legacySession: UserSession
    do {
      legacySession = try JSONDecoder().decode(UserSession.self, from: legacyData)
    } catch {
      Logger.matrixClient.error("Legacy session is unreadable, leaving it in place: \(error)")
      return
    }

    Logger.matrixClient.info("Migrating legacy session to store \(legacySession.storeID)")
    try save(legacySession)
    guard try load(storeID: legacySession.storeID) == legacySession else {
      throw AccountStoreError.migrationVerificationFailed
    }
    if lastFocusedStoreID == nil {
      lastFocusedStoreID = legacySession.storeID
    }
    defaults.set(Self.currentSchemaVersion, forKey: DefaultsKey.schemaVersion)
    removeLegacySession()
  }

  /// The session is already migrated at this point, so failing to remove the old copy must not
  /// fail the migration; it is retried on the next launch.
  private func removeLegacySession() {
    do {
      try keychain.delete(forKey: Self.legacySessionKey)
    } catch {
      Logger.matrixClient.error("Failed to remove legacy session, will retry: \(error)")
    }
  }
}

enum AccountStoreError: Error {
  case migrationVerificationFailed
}

import Foundation
import MatrixRustSDK
import Synchronization
import Testing

@testable import MatrixIntegration

final class FakeKeychain: KeychainStore, Sendable {
  let items = Mutex<[String: Data]>([:])
  let failingDeletes = Mutex<Set<String>>([])

  func save(_ data: Data, forKey key: String) throws {
    items.withLock { $0[key] = data }
  }

  func load(forKey key: String) throws -> Data? {
    items.withLock { $0[key] }
  }

  func delete(forKey key: String) throws {
    if failingDeletes.withLock({ $0.contains(key) }) {
      throw KeychainError.unexpectedStatus(-1)
    }
    items.withLock { $0[key] = nil }
  }

  func keys(withPrefix prefix: String) throws -> [String] {
    items.withLock { Array($0.keys) }.filter { $0.hasPrefix(prefix) }
  }
}

func makeUserSession(storeID: String, userID: String = "@alice:example.org", token: String = "t")
  -> UserSession
{
  UserSession(
    session: Session(
      accessToken: token, refreshToken: nil, userId: userID, deviceId: "DEVICE",
      homeserverUrl: "https://example.org", oauthData: nil, slidingSyncVersion: .native),
    storeID: storeID, storePassphrase: "passphrase")
}

struct AccountStoreTests {
  let keychain = FakeKeychain()
  let defaults: UserDefaults
  let store: AccountStore

  init() {
    let suite = "AccountStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    store = AccountStore(keychain: keychain, defaults: defaults)
  }

  func storeLegacy(_ session: UserSession) throws {
    try keychain.save(JSONEncoder().encode(session), forKey: AccountStore.legacySessionKey)
  }

  @Test func freshInstallHasNoAccounts() throws {
    try store.migrateLegacyIfNeeded()
    #expect(try store.loadAll().isEmpty)
    #expect(store.lastFocusedStoreID == nil)
    #expect(defaults.integer(forKey: AccountStore.DefaultsKey.schemaVersion) == 1)
  }

  @Test func migratesLegacySession() throws {
    let legacy = makeUserSession(storeID: "A")
    try storeLegacy(legacy)

    try store.migrateLegacyIfNeeded()

    #expect(try store.loadAll() == [legacy])
    #expect(store.lastFocusedStoreID == "A")
    #expect(try keychain.load(forKey: AccountStore.legacySessionKey) == nil)
  }

  @Test func migrationIsIdempotent() throws {
    let legacy = makeUserSession(storeID: "A")
    try storeLegacy(legacy)

    try store.migrateLegacyIfNeeded()
    try store.migrateLegacyIfNeeded()

    #expect(try store.loadAll() == [legacy])
  }

  @Test func interruptedMigrationRemovesLegacyWithoutOverwritingNewerSession() throws {
    let legacy = makeUserSession(storeID: "A", token: "old")
    try storeLegacy(legacy)
    keychain.failingDeletes.withLock { $0.insert(AccountStore.legacySessionKey) }

    // The legacy item survives the first run. The migrated account is still usable.
    try store.migrateLegacyIfNeeded()
    #expect(try keychain.load(forKey: AccountStore.legacySessionKey) != nil)
    #expect(try store.loadAll() == [legacy])

    // The SDK refreshes the token before the next launch.
    let refreshed = makeUserSession(storeID: "A", token: "new")
    try store.save(refreshed)

    keychain.failingDeletes.withLock { $0.removeAll() }
    try store.migrateLegacyIfNeeded()

    #expect(try store.loadAll() == [refreshed])
    #expect(try keychain.load(forKey: AccountStore.legacySessionKey) == nil)
  }

  @Test func unreadableLegacySessionIsKept() throws {
    try keychain.save(Data("not json".utf8), forKey: AccountStore.legacySessionKey)

    try store.migrateLegacyIfNeeded()

    #expect(try store.loadAll().isEmpty)
    #expect(try keychain.load(forKey: AccountStore.legacySessionKey) == Data("not json".utf8))
  }

  @Test func accountsAreIsolated() throws {
    let a = makeUserSession(storeID: "A", userID: "@a:example.org")
    let b = makeUserSession(storeID: "B", userID: "@b:example.org")
    try store.save(a)
    try store.save(b)

    let refreshedA = makeUserSession(storeID: "A", userID: "@a:example.org", token: "new")
    try store.save(refreshedA)
    #expect(try store.load(storeID: "B") == b)

    try store.remove(storeID: "A")
    #expect(try store.loadAll() == [b])
  }

  @Test func preservesOrderAndPrunesMissingAccounts() throws {
    try store.save(makeUserSession(storeID: "B"))
    try store.save(makeUserSession(storeID: "A"))
    try store.save(makeUserSession(storeID: "C"))
    #expect(try store.loadAll().map(\.storeID) == ["B", "A", "C"])

    // An item removed behind our back is dropped from the order.
    try keychain.delete(forKey: AccountStore.sessionKey(for: "A"))
    #expect(try store.loadAll().map(\.storeID) == ["B", "C"])
    #expect(defaults.stringArray(forKey: AccountStore.DefaultsKey.order) == ["B", "C"])
  }

  @Test func removingActiveAccountClearsActive() throws {
    try store.save(makeUserSession(storeID: "A"))
    store.lastFocusedStoreID = "A"
    try store.remove(storeID: "A")
    #expect(store.lastFocusedStoreID == nil)
  }

  @Test func skipsUnreadableSessions() throws {
    try store.save(makeUserSession(storeID: "A"))
    try keychain.save(Data("garbage".utf8), forKey: AccountStore.sessionKey(for: "B"))
    #expect(try store.loadAll().map(\.storeID) == ["A"])
  }
}

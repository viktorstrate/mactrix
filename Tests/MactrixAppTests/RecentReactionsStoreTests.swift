import Observation
import Synchronization
import Testing

@testable import MatrixIntegration

@MainActor
struct RecentReactionsStoreTests {
  @Test func cachedKeysNotifiesObserversWhenRefreshed() async {
    let client = FakeRecentReactionsClient(keys: ["❤", "👍🏽"])
    let store = RecentReactionsStore(client: client)
    let changed = Mutex(false)

    withObservationTracking {
      _ = store.cachedKeys
    } onChange: {
      changed.withLock { $0 = true }
    }

    #expect(!changed.withLock { $0 })
    _ = await store.refresh()
    #expect(changed.withLock { $0 })
    #expect(store.cachedKeys == ["❤", "👍🏽"])
  }

  @Test func successfulLoadPreservesExactSDKKeysAndOrder() async {
    let keys = ["👍🏽", "❤", "❤️", "custom-reaction", "👍", "❤", ""]
    let client = FakeRecentReactionsClient(keys: keys)
    let store = RecentReactionsStore(client: client)
    #expect(store.cachedKeys.isEmpty)
    #expect(store.isActive)

    let result = await store.refresh()

    #expect(result == keys)
    #expect(store.cachedKeys.map { Array($0.utf8) } == keys.map { Array($0.utf8) })
    #expect(client.loadCount == 1)
  }

  @Test func emptyLoadReplacesCachedKeys() async {
    let client = FakeRecentReactionsClient(keys: ["😀"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    client.keys = []

    let result = await store.refresh()

    #expect(result == [])
    #expect(store.cachedKeys.isEmpty)
  }

  @Test func failedLoadReturnsNilAndKeepsCache() async {
    let client = FakeRecentReactionsClient(keys: ["😀"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    client.loadError = .failed

    let result = await store.refresh()

    #expect(result == nil)
    #expect(store.cachedKeys == ["😀"])
  }

  @Test func invalidationRejectsPendingAndFutureLoadsWithoutClearingCache() async {
    let client = FakeRecentReactionsClient(keys: ["😀"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    let load = SuspendedResult<[String]>()
    client.loadHandler = { try await load.call() }
    let task = Task { await store.refresh() }
    await load.waitUntilStarted()

    store.invalidate()
    store.invalidate()
    load.resume(returning: ["stale"])
    let result = await task.value
    let subsequent = await store.refresh()

    #expect(!store.isActive)
    #expect(result == nil)
    #expect(subsequent == nil)
    #expect(store.cachedKeys == ["😀"])
    #expect(client.loadCount == 2)
  }

  @Test func cancellationBeforeRefreshDoesNotLoad() async {
    let client = FakeRecentReactionsClient(keys: ["😀"])
    let store = RecentReactionsStore(client: client)
    let task = Task { await store.refresh() }
    task.cancel()

    let result = await task.value

    #expect(result == nil)
    #expect(client.loadCount == 0)
    #expect(store.cachedKeys.isEmpty)
  }

  @Test func cancelledLoadCannotApplyEvenWhenClientIgnoresCancellation() async {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    let load = SuspendedResult<[String]>()
    client.loadHandler = { try await load.call() }
    let task = Task { await store.refresh() }
    await load.waitUntilStarted()

    task.cancel()
    load.resume(returning: ["cancelled"])
    let result = await task.value

    #expect(result == nil)
    #expect(store.cachedKeys == ["cached"])
  }

  @Test func clientCancellationErrorReturnsNilAndKeepsCache() async {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    client.loadHandler = { throw CancellationError() }

    let result = await store.refresh()

    #expect(result == nil)
    #expect(store.cachedKeys == ["cached"])
  }

  @Test func latestRequestWinsWhenLoadsCompleteOutOfOrder() async {
    let client = FakeRecentReactionsClient()
    let store = RecentReactionsStore(client: client)
    let firstLoad = SuspendedResult<[String]>()
    let secondLoad = SuspendedResult<[String]>()
    client.loadHandler = { try await firstLoad.call() }
    let first = Task { await store.refresh() }
    await firstLoad.waitUntilStarted()
    client.loadHandler = { try await secondLoad.call() }
    let second = Task { await store.refresh() }
    await secondLoad.waitUntilStarted()

    secondLoad.resume(returning: ["new"])
    let secondResult = await second.value
    firstLoad.resume(returning: ["old"])
    let firstResult = await first.value

    #expect(secondResult == ["new"])
    #expect(firstResult == nil)
    #expect(store.cachedKeys == ["new"])
  }

  @Test func failedLatestRequestStillSupersedesOlderLoad() async {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    let load = SuspendedResult<[String]>()
    client.loadHandler = { try await load.call() }
    let older = Task { await store.refresh() }
    await load.waitUntilStarted()
    client.loadHandler = nil
    client.loadError = .failed

    let latestResult = await store.refresh()
    load.resume(returning: ["stale"])
    let olderResult = await older.value

    #expect(latestResult == nil)
    #expect(olderResult == nil)
    #expect(store.cachedKeys == ["cached"])
  }

  @Test func additionWritesExactKeyThenUsesSDKOrder() async throws {
    let client = FakeRecentReactionsClient(keys: ["other", "👍🏽", "❤"])
    let store = RecentReactionsStore(client: client)
    var operationCount = 0

    try await store.toggleReaction("❤") {
      operationCount += 1
      #expect(client.addedKeys.isEmpty)
      #expect(client.loadCount == 0)
      return true
    }

    #expect(operationCount == 1)
    #expect(client.addedKeys == ["❤"])
    #expect(client.loadCount == 1)
    #expect(store.cachedKeys == ["other", "👍🏽", "❤"])
  }

  @Test func removalDoesNotWriteOrRefresh() async throws {
    let client = FakeRecentReactionsClient()
    let store = RecentReactionsStore(client: client)

    try await store.toggleReaction("😀") { false }

    #expect(client.addedKeys.isEmpty)
    #expect(client.loadCount == 0)
  }

  @Test func failedTogglePropagatesWithoutWritingOrRefreshing() async {
    let client = FakeRecentReactionsClient()
    let store = RecentReactionsStore(client: client)

    do {
      try await store.toggleReaction("😀") { throw RecentReactionsTestError.failed }
      Issue.record("Expected the reaction operation's error to propagate")
    } catch {
      #expect(error as? RecentReactionsTestError == .failed)
    }

    #expect(client.addedKeys.isEmpty)
    #expect(client.loadCount == 0)
  }

  @Test func failedRecentWriteDoesNotThrowOrChangeCache() async throws {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    client.addError = .failed

    try await store.toggleReaction("👍🏽") { true }

    #expect(client.addedKeys == ["👍🏽"])
    #expect(client.loadCount == 1)
    #expect(store.cachedKeys == ["cached"])
  }

  @Test func successfulWriteRefreshesWithoutWaitingForOverlappingFailure() async throws {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    let successfulWrite = SuspendedResult<Void>()
    let failedWrite = SuspendedResult<Void>()
    client.addHandler = { key in
      if key == "❤" {
        try await successfulWrite.call()
        client.keys = ["❤", "cached"]
      } else {
        try await failedWrite.call()
        throw RecentReactionsTestError.failed
      }
    }

    let first = Task { try await store.toggleReaction("❤") { true } }
    await successfulWrite.waitUntilStarted()
    let second = Task { try await store.toggleReaction("👍🏽") { true } }
    await failedWrite.waitUntilStarted()

    successfulWrite.resume(returning: ())
    try await first.value
    #expect(client.loadCount == 2)
    #expect(store.cachedKeys == ["❤", "cached"])

    failedWrite.resume(returning: ())
    try await second.value
    #expect(client.addedKeys == ["❤", "👍🏽"])
    #expect(client.loadCount == 2)
    #expect(store.cachedKeys == ["❤", "cached"])
  }

  @Test func storesKeepIndependentCachesAndLifecycles() async throws {
    let firstClient = FakeRecentReactionsClient(keys: ["❤"])
    let secondClient = FakeRecentReactionsClient(keys: ["👍🏽"])
    let firstStore = RecentReactionsStore(client: firstClient)
    let secondStore = RecentReactionsStore(client: secondClient)

    _ = await firstStore.refresh()
    #expect(secondStore.cachedKeys.isEmpty)
    _ = await secondStore.refresh()
    #expect(firstStore.cachedKeys == ["❤"])
    #expect(secondStore.cachedKeys == ["👍🏽"])

    firstClient.keys = ["😀", "❤"]
    try await firstStore.toggleReaction("😀") { true }
    #expect(firstStore.cachedKeys == ["😀", "❤"])
    #expect(secondStore.cachedKeys == ["👍🏽"])
    #expect(secondClient.addedKeys.isEmpty)
    #expect(secondClient.loadCount == 1)

    firstStore.invalidate()
    secondClient.keys = ["❤️", "👍🏽"]
    try await secondStore.toggleReaction("❤️") { true }
    #expect(!firstStore.isActive)
    #expect(secondStore.isActive)
    #expect(firstStore.cachedKeys == ["😀", "❤"])
    #expect(secondStore.cachedKeys == ["❤️", "👍🏽"])
    #expect(firstClient.addedKeys == ["😀"])
    #expect(secondClient.addedKeys == ["❤️"])
  }

  @Test func failedRefreshAfterSuccessfulWriteDoesNotThrow() async throws {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    client.loadError = .failed

    try await store.toggleReaction("😀") { true }

    #expect(client.addedKeys == ["😀"])
    #expect(client.loadCount == 2)
    #expect(store.cachedKeys == ["cached"])
  }

  @Test(arguments: [false, true])
  func inactiveOrCancelledToggleDoesNotWrite(cancel: Bool) async throws {
    let client = FakeRecentReactionsClient()
    let store = RecentReactionsStore(client: client)
    let operation = SuspendedResult<Bool>()
    let task = Task {
      try await store.toggleReaction("😀") { try await operation.call() }
    }
    await operation.waitUntilStarted()

    if cancel { task.cancel() } else { store.invalidate() }
    operation.resume(returning: true)
    try await task.value

    #expect(client.addedKeys.isEmpty)
    #expect(client.loadCount == 0)
  }

  @Test(arguments: [false, true])
  func invalidationOrCancellationDuringWritePreventsRefresh(cancel: Bool) async throws {
    let client = FakeRecentReactionsClient()
    let store = RecentReactionsStore(client: client)
    let write = SuspendedResult<Void>()
    client.addHandler = { _ in try await write.call() }
    let task = Task { try await store.toggleReaction("😀") { true } }
    await write.waitUntilStarted()

    if cancel { task.cancel() } else { store.invalidate() }
    write.resume(returning: ())
    try await task.value

    #expect(client.addedKeys == ["😀"])
    #expect(client.loadCount == 0)
    #expect(store.cachedKeys.isEmpty)
  }

  @Test func mutationRejectsEarlierReadBeforePostWriteRefreshStarts() async throws {
    let client = FakeRecentReactionsClient(keys: ["cached"])
    let store = RecentReactionsStore(client: client)
    _ = await store.refresh()
    let load = SuspendedResult<[String]>()
    client.loadHandler = { try await load.call() }
    let olderRead = Task { await store.refresh() }
    await load.waitUntilStarted()
    let write = SuspendedResult<Void>()
    client.addHandler = { _ in try await write.call() }
    let toggle = Task { try await store.toggleReaction("❤") { true } }
    await write.waitUntilStarted()

    load.resume(returning: ["stale"])
    let olderResult = await olderRead.value
    #expect(olderResult == nil)
    #expect(store.cachedKeys == ["cached"])
    client.loadHandler = nil
    let duringWrite = await store.refresh()
    #expect(duringWrite == ["cached"])
    #expect(client.loadCount == 3)
    client.keys = ["❤", "cached"]
    write.resume(returning: ())
    try await toggle.value
    #expect(store.cachedKeys == ["❤", "cached"])
    #expect(client.loadCount == 4)
  }
}

private enum RecentReactionsTestError: Error {
  case failed
}

@MainActor
private final class FakeRecentReactionsClient: RecentReactionsClient {
  var keys: [String]
  var loadError: RecentReactionsTestError?
  var addError: RecentReactionsTestError?
  var loadHandler: (@MainActor () async throws -> [String])?
  var addHandler: (@MainActor (String) async throws -> Void)?
  private(set) var loadCount = 0
  private(set) var addedKeys: [String] = []

  init(keys: [String] = []) {
    self.keys = keys
  }

  func load() async throws -> [String] {
    loadCount += 1
    if let loadHandler { return try await loadHandler() }
    if let loadError { throw loadError }
    return keys
  }

  func add(_ key: String) async throws {
    addedKeys.append(key)
    if let addHandler { try await addHandler(key) }
    if let addError { throw addError }
  }
}

/// Deliberately ignores cancellation so tests can verify the store's own guards.
@MainActor
private final class SuspendedResult<Value: Sendable> {
  private var continuation: CheckedContinuation<Value, any Error>?
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func call() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      precondition(!started)
      self.continuation = continuation
      started = true
      let waiters = startWaiters
      startWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resume(returning value: Value) {
    precondition(continuation != nil)
    continuation?.resume(returning: value)
    continuation = nil
  }
}

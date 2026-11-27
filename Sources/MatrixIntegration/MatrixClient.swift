import AppKit
import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Observation
import Security
import UniformTypeIdentifiers
import Utils

@MainActor @Observable
public class MatrixClient {
  public let storeID: String
  /// The Matrix user ID of this account.
  public let userID: String
  @ObservationIgnored let roomSubscriptions = RoomSubscriptions()
  @ObservationIgnored public private(set) lazy var recentReactions = RecentReactionsStore(
    client: SDKRecentReactionsClient(client: client))
  private let storePassphrase: String
  @ObservationIgnored nonisolated let accountStore: AccountStore
  public internal(set) var client: ClientProtocol!

  public internal(set) var rooms: [SidebarRoom] = []

  public internal(set) var spaceService: LiveSpaceService!

  private var clientDelegateHandle: TaskHandle?
  public internal(set) var authenticationFailed: Bool = false

  /// This account's own display name and avatar, for identifying the account in the UI.
  public private(set) var ownDisplayName: String?
  public private(set) var ownAvatarUrl: String?

  public let notifications: MatrixNotifications

  public let viaServers = ["matrix.org"]

  public func routingServers(hints: [String]) -> [String] {
    var seen = Set<String>()
    return (hints + viaServers).filter { seen.insert($0).inserted }
  }

  init(userSession: UserSession, accountStore: AccountStore) async throws {
    storeID = userSession.storeID
    userID = userSession.userID
    notifications = MatrixNotifications(accountID: userSession.storeID)
    storePassphrase = userSession.storePassphrase
    self.accountStore = accountStore

    client = try await Self.clientBuilder(
      homeserver: .stored(url: userSession.homeserverURL), storeId: storeID,
      storePassphrase: storePassphrase
    )
    // .enableOidcRefreshLock()
    .setSessionDelegate(sessionDelegate: self)
    .build()

    try await client.restoreSession(session: userSession.session)

    spaceService = LiveSpaceService(client: self.client, spaceService: await client.spaceService())
    clientDelegateHandle = try? client.setDelegate(delegate: self)
  }

  init(
    storeID: String, storePassphrase: String, client: ClientProtocol, accountStore: AccountStore
  ) async throws {
    self.storeID = storeID
    self.userID = try client.userId()
    notifications = MatrixNotifications(accountID: storeID)
    self.storePassphrase = storePassphrase
    self.accountStore = accountStore
    self.client = client

    spaceService = LiveSpaceService(client: self.client, spaceService: await client.spaceService())
    clientDelegateHandle = try? self.client.setDelegate(delegate: self)
  }

  func userSession() throws -> UserSession {
    return try UserSession(
      session: client.session(), storeID: storeID, storePassphrase: storePassphrase)
  }

  /// The most connections each of an account's SQLite databases keeps open.
  ///
  /// The SDK otherwise sizes each pool at four connections per CPU core. With four databases per
  /// account and two file descriptors per connection, a few accounts would then exhaust the
  /// process's file descriptors, failing database opens, network requests, and rendering.
  static let sqlitePoolMaxSize: UInt32 = 8

  /// Where a client's homeserver comes from.
  enum Homeserver {
    /// A server name or URL entered at sign-in. Building the client looks up the homeserver and
    /// checks that it supports native sliding sync, which takes network requests.
    case discover(serverNameOrURL: String)
    /// The homeserver of a stored session, which already uses native sliding sync. Building the
    /// client takes no network requests, so restoring at launch doesn't wait for, or need, the
    /// network.
    case stored(url: String)
  }

  static func clientBuilder(homeserver: Homeserver, storeId: String, storePassphrase: String)
    -> ClientBuilder
  {
    let sqliteConfig = SqliteStoreBuilder(
      dataPath: StoreDirectories.data(for: storeId).path(percentEncoded: false),
      cachePath: StoreDirectories.caches(for: storeId).path(percentEncoded: false)
    )
    .passphrase(passphrase: storePassphrase)
    .poolMaxSize(poolMaxSize: sqlitePoolMaxSize)

    let builder = ClientBuilder()
      .sqliteStore(config: sqliteConfig)
      .withSearchIndexStore(
        path: StoreDirectories.caches(for: storeId).appending(component: "SearchIndex")
          .path(percentEncoded: false),
        key: storePassphrase
      )
      .threadsEnabled(enabled: true, threadSubscriptions: true)
      .autoEnableCrossSigning(autoEnableCrossSigning: true)
      .userAgent(userAgent: "Mactrix macOS")

    switch homeserver {
    case .discover(let serverNameOrURL):
      return
        builder
        .serverNameOrHomeserverUrl(serverNameOrUrl: serverNameOrURL)
        .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
    case .stored(let url):
      return
        builder
        .homeserverUrl(url: url)
        .slidingSyncVersionBuilder(versionBuilder: .native)
    }
  }

  struct SecureRandomBytesError: LocalizedError {
    let code: Int32

    var errorDescription: String? {
      "Failed to generate secure bytes with status code \(code)"
    }
  }

  static func generateStorePassphrase() throws -> String {
    var result = [UInt8](repeating: UInt8.random(in: 0..<UInt8.max), count: 32)
    let status = unsafe SecRandomCopyBytes(kSecRandomDefault, result.count, &result)
    if status != errSecSuccess {
      throw SecureRandomBytesError(code: status)
    }

    return Data(result).base64EncodedString()
  }

  public static func loginDetails(homeServer: String) async throws -> HomeserverLogin {
    let storeID = UUID().uuidString
    let storePassphrase = try Self.generateStorePassphrase()

    let client = try await Self.clientBuilder(
      homeserver: .discover(serverNameOrURL: homeServer), storeId: storeID,
      storePassphrase: storePassphrase
    ).build()

    let details = await client.homeserverLoginDetails()
    return HomeserverLogin(
      storeID: storeID, storePassphrase: storePassphrase, unauthenticatedClient: client,
      loginDetails: details)
  }

  /// Restores every stored account. Accounts that fail to restore are skipped and logged.
  public static func restoreAll(accountStore: AccountStore) async -> [MatrixClient] {
    let sessions: [UserSession]
    do {
      try accountStore.migrateLegacyIfNeeded()
      removeOrphanedStores(accountStore: accountStore)
      sessions = try accountStore.loadAll()
    } catch {
      Logger.matrixClient.error("Failed to load stored accounts: \(error)")
      return []
    }

    // Start every restore before awaiting any, so launch waits for the slowest account rather
    // than all of them in turn. Awaiting in order keeps the stored account order.
    let restores = sessions.map { session in
      Task { @MainActor in
        try await MatrixClient(userSession: session, accountStore: accountStore)
      }
    }
    var clients: [MatrixClient] = []
    for (session, restore) in zip(sessions, restores) {
      do {
        clients.append(try await restore.value)
      } catch {
        Logger.matrixClient.error("Failed to restore store \(session.storeID): \(error)")
      }
    }
    return clients
  }

  /// Deletes store directories left behind by abandoned logins.
  static func removeOrphanedStores(accountStore: AccountStore) {
    do {
      // An unmigrated legacy session's store isn't listed yet, so it must not be swept.
      guard try !accountStore.hasLegacySession() else { return }
      StoreDirectories.removeOrphans(
        in: [StoreDirectories.dataRoot, StoreDirectories.cachesRoot],
        keeping: try accountStore.allStoreIDs(),
        createdBefore: Date.now.addingTimeInterval(-10 * 60))
    } catch {
      Logger.matrixClient.error("Skipping orphaned store cleanup: \(error)")
    }
  }

  public func reset() async throws {
    recentReactions.invalidate()
    isResettingSession = true
    offlineRestartTask?.cancel()
    await roomSubscriptions.invalidate()
    // A start in flight stops at its next step; wait so it can't start syncing a signed-out
    // session after the stop below.
    await syncStartTask?.value
    await syncService?.stop()
    Logger.matrixClient.debug("matrix client sign out, store \(self.storeID)")
    try? await client.logout()
    try? FileManager.default.removeItem(at: StoreDirectories.data(for: storeID))
    try? FileManager.default.removeItem(at: StoreDirectories.caches(for: storeID))
    try accountStore.remove(storeID: storeID)
    Logger.matrixClient.debug("matrix client sign out complete, store \(self.storeID)")
  }

  public internal(set) var syncService: SyncService?
  public internal(set) var syncState: SyncServiceState = .terminated
  public internal(set) var roomListService: RoomListService? {
    didSet { roomSubscriptions.setService(roomListService) }
  }
  public internal(set) var roomListServiceState: RoomListServiceState?
  public internal(set) var showRoomSyncIndicator: RoomListServiceSyncIndicator?
  public internal(set) var ignoredUserIds: [String] = []

  @ObservationIgnored fileprivate var roomListEntriesHandle:
    RoomListEntriesWithDynamicAdaptersResult?
  @ObservationIgnored fileprivate var roomListServiceStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var syncIndicatorHandle: TaskHandle?
  @ObservationIgnored fileprivate var syncStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var verificationStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var recoveryStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var backupStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var ignoredUsersHandle: TaskHandle?

  /// The latest session verification request received by another client
  public var sessionVerificationRequest: SessionVerificationRequestDetails?
  public var sessionVerificationData: SessionVerificationData?
  public var verificationState: VerificationState?
  public internal(set) var recoveryState: RecoveryState?
  public internal(set) var backupState: BackupState?

  public enum ServerBackupState {
    case unknown
    case loading
    case available(Bool)
    case failed
  }

  public private(set) var serverBackupState: ServerBackupState = .unknown
  public private(set) var isRecoveringWithRecoveryKey = false
  @ObservationIgnored private var isResettingSession = false

  public func verifyWithRecoveryKey(_ recoveryKey: String) async throws {
    guard !isResettingSession else { throw CancellationError() }
    guard !isRecoveringWithRecoveryKey else {
      throw RecoveryKeyVerificationError.alreadyInProgress
    }

    isRecoveringWithRecoveryKey = true
    let encryption = client.encryption()
    defer {
      isRecoveringWithRecoveryKey = false
      // Recovery can import some secrets before failing. Read the actual SDK state in either case.
      if !isResettingSession {
        verificationState = encryption.verificationState()
        recoveryState = encryption.recoveryState()
        backupState = encryption.backupState()
      }
    }

    try Task.checkCancellation()
    try await encryption.recover(recoveryKey: recoveryKey)
    try Task.checkCancellation()
    guard !isResettingSession else { throw CancellationError() }
  }

  public func refreshServerBackupState() async {
    if case .loading = serverBackupState { return }
    serverBackupState = .loading
    do {
      let exists = try await client.encryption().backupExistsOnServer()
      try Task.checkCancellation()
      serverBackupState = .available(exists)
    } catch {
      serverBackupState = Task.isCancelled ? .unknown : .failed
    }
  }

  var notificationClient: NotificationClient?

  /// Account setup that comes with syncing.
  ///
  /// Some steps fail while the homeserver can't be reached, so none of them stop the sync loop from
  /// starting. A failed step is retried whenever sync comes back online.
  enum SyncSetupStep: String, CaseIterable {
    case roomList = "room list"
    case notifications
    case verification
    case ignoredUsers = "ignored users"
    case ownProfile = "own profile"
  }

  /// The setup steps that haven't succeeded yet.
  @ObservationIgnored private var pendingSetupSteps = SyncSetupStep.allCases
  @ObservationIgnored private var setupRetryTask: Task<Void, Never>?

  /// Whether a call to `startSync()` is in flight.
  public private(set) var isStartingSync = false
  @ObservationIgnored private var syncStartTask: Task<Void, Never>?

  /// Starts syncing, or restarts a sync that stopped, failed, or went offline.
  ///
  /// Calls made while a start is in flight wait for it instead of starting another, so this is
  /// safe to call repeatedly.
  public func startSync() async {
    if let syncStartTask {
      await syncStartTask.value
      return
    }
    let task = Task { await performStartSync() }
    syncStartTask = task
    isStartingSync = true
    await task.value
    syncStartTask = nil
    isStartingSync = false
  }

  /// The Mac's network connection. Without one, an offline account isn't restarted until it
  /// comes back, and on a connection that saves data it's restarted fewer times.
  @ObservationIgnored public var networkConditions = NetworkConditions()

  @ObservationIgnored private var offlineRestartTask: Task<Void, Never>?

  /// How long to wait before each restart of an offline account. Each wait is shortened by up to
  /// half at random, so clients of a homeserver that went down don't all retry at once.
  static let offlineRestartDelays: [Duration] = [2, 4, 8, 16, 30].map { .seconds($0) }

  /// The waits used instead of `offlineRestartDelays` in Low Power Mode or on a connection that
  /// saves data, where each restart's new connection and full sync request cost more.
  static let savingOfflineRestartDelays: [Duration] = [5, 20].map { .seconds($0) }

  /// The waits before each restart of an offline account, given the current power and network.
  private var currentOfflineRestartDelays: [Duration] {
    ProcessInfo.processInfo.isLowPowerModeEnabled || networkConditions.isSavingData
      ? Self.savingOfflineRestartDelays : Self.offlineRestartDelays
  }

  /// Restarts sync a few times while the account stays offline, at `currentOfflineRestartDelays`,
  /// then leaves reconnecting to the sync service's offline mode. Turning on Low Power Mode or
  /// moving to a connection that saves data partway through cuts the round short.
  ///
  /// The sync service's offline mode only reconnects once a reachability check succeeds, and a
  /// check on a connection that went dead when the network changed hangs until it times out,
  /// keeping the account offline for a minute or more. A restart cancels that check and tries
  /// again at once. A homeserver that's down or unreachable can stay that way for a long time,
  /// though, and offline mode keeps checking on its own, so restarting for longer would only
  /// spend battery. Going offline again, or the network coming back, starts another round.
  func scheduleOfflineRestarts() {
    guard offlineRestartTask == nil, !isResettingSession else { return }
    offlineRestartTask = Task { [weak self] in
      var restarts = 0
      while let delays = self?.currentOfflineRestartDelays, restarts < delays.count {
        try? await Task.sleep(for: delays[restarts] * Double.random(in: 0.5...1))
        // A restart briefly reports running before it can fail again, so only a later check
        // that finds the account online ends the restarts. Errors other than being offline
        // aren't the network's, so restarting wouldn't help them. Without a network, the
        // restart when it comes back takes over.
        guard let self, !Task.isCancelled, [.offline, .idle].contains(self.syncState),
          !self.isResettingSession, !self.authenticationFailed, self.networkConditions.isAvailable
        else { break }
        await self.startSync()
        restarts += 1
      }
      if !Task.isCancelled {
        self?.offlineRestartTask = nil
      }
    }
  }

  private func performStartSync() async {
    guard !isResettingSession, !authenticationFailed else { return }
    // Once built, the sync service is only restarted, keeping its listeners. Its `start()` does
    // nothing while running, and reconnects straight away when offline.
    if let syncService {
      Logger.matrixClient.info(
        "Restarting sync from \(String(describing: self.syncState), privacy: .public), store \(self.storeID)"
      )
      await syncService.start()
      retryPendingSetupSteps()
      await client.enableAllSendQueues(enable: true)
      return
    }
    do {
      try await setUpSync()
    } catch {
      Logger.matrixClient.error("Failed to start sync, store \(self.storeID): \(error)")
    }
  }

  private func setUpSync() async throws {
    let _syncService = try await client.syncService().withOfflineMode().finish()
    guard !isResettingSession else { return }
    syncService = _syncService

    syncStateHandle = _syncService.state(listener: self)

    let _roomListService = _syncService.roomListService()
    roomListService = _roomListService
    roomListServiceStateHandle = _roomListService.state(listener: self)
    syncIndicatorHandle = _roomListService.syncIndicator(
      delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: self)

    let encryption = client.encryption()
    verificationStateHandle = encryption.verificationStateListener(listener: self)
    recoveryStateHandle = encryption.recoveryStateListener(listener: self)
    backupStateHandle = encryption.backupStateListener(listener: self)

    ignoredUsersHandle = client.subscribeToIgnoredUsers(listener: self)

    // The room list and notification handler come from the local store. Set them up before the
    // first sync, so it doesn't miss rooms or notifications. No retry can overlap this: retries
    // only start once sync is running.
    await runSetupSteps([.roomList, .notifications])
    guard !isResettingSession else { return }

    // Start the sync loop. In offline mode it keeps retrying until the homeserver can be reached.
    await _syncService.start()
    Logger.matrixClient.info("Matrix sync started, store \(self.storeID)")

    retryPendingSetupSteps()
  }

  /// Retries the setup steps that haven't succeeded yet, unless a retry is already running.
  func retryPendingSetupSteps() {
    guard setupRetryTask == nil, !pendingSetupSteps.isEmpty, !isResettingSession else { return }
    setupRetryTask = Task { [weak self] in
      guard let self else { return }
      await self.runSetupSteps(self.pendingSetupSteps)
      self.setupRetryTask = nil
    }
  }

  /// Runs each of `steps` that is still pending, keeping the ones that fail for a later retry.
  private func runSetupSteps(_ steps: [SyncSetupStep]) async {
    for step in steps where pendingSetupSteps.contains(step) {
      guard !isResettingSession else { return }
      do {
        try await runSetupStep(step)
        pendingSetupSteps.removeAll { $0 == step }
      } catch {
        Logger.matrixClient.error(
          "Sync setup step \(step.rawValue, privacy: .public) failed, store \(self.storeID): \(error)"
        )
      }
    }
  }

  private func runSetupStep(_ step: SyncSetupStep) async throws {
    switch step {
    case .roomList:
      guard let roomListService else { return }
      let roomEntriesListener = AsyncSDKListener<[RoomListEntriesUpdate]>()
      let _roomListEntriesHandle = try await roomListService.allRooms()
        .entriesWithDynamicAdapters(pageSize: 100, listener: roomEntriesListener)
      _ = _roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))
      roomListEntriesHandle = _roomListEntriesHandle

      Task { [weak self] in
        for await roomEntries in roomEntriesListener {
          guard let self else { break }
          self.updateRoomEntries(roomEntriesUpdate: roomEntries)
        }
      }
    case .notifications:
      guard let syncService else { return }
      notificationClient = try await client.notificationClient(
        processSetup: .singleProcess(syncService: syncService))
      await client.registerNotificationHandler(listener: notifications)
    case .verification:
      try await client.getSessionVerificationController().setDelegate(delegate: self)
    case .ignoredUsers:
      ignoredUserIds = try await client.ignoredUsers()
    case .ownProfile:
      try await loadOwnProfile()
    }
  }

  /// Reloads `ownDisplayName` and `ownAvatarUrl`, falling back to cached values when offline.
  public func refreshOwnProfile() async {
    try? await loadOwnProfile()
  }

  /// Reloads `ownDisplayName` and `ownAvatarUrl`, throwing if the homeserver can't be reached. The
  /// cached avatar fills in while there is none yet.
  private func loadOwnProfile() async throws {
    let displayName: String
    do {
      displayName = try await client.displayName()
    } catch {
      if ownAvatarUrl == nil {
        ownAvatarUrl = try? await client.cachedAvatarUrl()
      }
      throw error
    }
    ownDisplayName = displayName
    if let avatarUrl = try? await client.avatarUrl() {
      ownAvatarUrl = avatarUrl
    } else if ownAvatarUrl == nil {
      ownAvatarUrl = try? await client.cachedAvatarUrl()
    }
  }

  public func clearCache() async throws {
    try await client.clearCaches(syncService: syncService)
  }

  public func isUserIgnored(_ userId: String) -> Bool {
    ignoredUserIds.contains(userId)
  }

  public func declineVerificationRequest(request: SessionVerificationRequestDetails) async throws {
    try await client.getSessionVerificationController().acknowledgeVerificationRequest(
      senderId: request.senderProfile.userId, flowId: request.flowId
    )

    try await client.getSessionVerificationController().cancelVerification()
  }

  public func acceptVerificationRequest(request: SessionVerificationRequestDetails) async throws {
    try await client.getSessionVerificationController().acknowledgeVerificationRequest(
      senderId: request.senderProfile.userId, flowId: request.flowId
    )

    try await client.getSessionVerificationController().acceptVerificationRequest()
  }

  public func requestDeviceVerification() async throws {
    try await client.getSessionVerificationController().requestDeviceVerification()
  }
}

private enum RecoveryKeyVerificationError: Error {
  case alreadyInProgress
}

enum MatrixClientRestoreSessionError: Error {
  case sessionNotFound, wrongUserId
}

extension MatrixClient: MatrixRustSDK.ClientSessionDelegate {
  public nonisolated func retrieveSessionFromKeychain(userId: String) throws
    -> MatrixRustSDK.Session
  {
    Logger.matrixClient.debug(
      "client session delegate: retrieve session from keychain: \(userId, privacy: .sensitive)")

    guard let userSession = try accountStore.load(storeID: storeID) else {
      throw MatrixClientRestoreSessionError.sessionNotFound
    }
    guard userSession.userID == userId else {
      Logger.matrixClient.debug(
        "restored user session has wrong userId: \(userSession.userID, privacy: .sensitive), expected \(userId, privacy: .sensitive)"
      )
      throw MatrixClientRestoreSessionError.wrongUserId
    }
    return userSession.session
  }

  public nonisolated func saveSessionInKeychain(session: MatrixRustSDK.Session) {
    Logger.matrixClient.debug("client session delegate: save session in keychain, store \(self.storeID)")
    do {
      try accountStore.save(
        UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase))
    } catch {
      Logger.matrixClient.error("failed to save session in keychain, store \(self.storeID): \(error)")
    }
  }
}

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
  @ObservationIgnored let roomSubscriptions = RoomSubscriptions()
  @ObservationIgnored public private(set) lazy var recentReactions = RecentReactionsStore(
    client: SDKRecentReactionsClient(client: client))
  private let storePassphrase: String
  @ObservationIgnored nonisolated let accountStore: AccountStore
  public internal(set) var client: ClientProtocol!

  public internal(set) var rooms: [SidebarRoom] = []

  @ObservationIgnored var lastAppliedDockUnreadCount: Int?

  public internal(set) var spaceService: LiveSpaceService!

  private var clientDelegateHandle: TaskHandle?
  public internal(set) var authenticationFailed: Bool = false

  public let notifications: MatrixNotifications = .init()

  public let viaServers = ["matrix.org"]

  public func routingServers(hints: [String]) -> [String] {
    var seen = Set<String>()
    return (hints + viaServers).filter { seen.insert($0).inserted }
  }

  init(userSession: UserSession, accountStore: AccountStore) async throws {
    storeID = userSession.storeID
    storePassphrase = userSession.storePassphrase
    self.accountStore = accountStore

    client = try await Self.clientBuilder(
      homeServer: userSession.homeserverURL, storeId: storeID, storePassphrase: storePassphrase
    )
    // .enableOidcRefreshLock()
    .setSessionDelegate(sessionDelegate: self)
    .build()

    try await client.restoreSession(session: userSession.session)

    spaceService = LiveSpaceService(client: self.client, spaceService: await client.spaceService())
    clientDelegateHandle = try? client.setDelegate(delegate: self)
    observeDockIconUnreadCount()
  }

  init(
    storeID: String, storePassphrase: String, client: ClientProtocol, accountStore: AccountStore
  ) async {
    self.storeID = storeID
    self.storePassphrase = storePassphrase
    self.accountStore = accountStore
    self.client = client

    spaceService = LiveSpaceService(client: self.client, spaceService: await client.spaceService())
    clientDelegateHandle = try? self.client.setDelegate(delegate: self)
    observeDockIconUnreadCount()
  }

  func userSession() throws -> UserSession {
    return try UserSession(
      session: client.session(), storeID: storeID, storePassphrase: storePassphrase)
  }

  static func clientBuilder(homeServer: String, storeId: String, storePassphrase: String)
    -> ClientBuilder
  {
    let sqliteConfig = SqliteStoreBuilder(
      dataPath: URL.sessionData(for: storeId).path(percentEncoded: false),
      cachePath: URL.sessionCaches(for: storeId).path(percentEncoded: false)
    )
    .passphrase(passphrase: storePassphrase)

    return ClientBuilder()
      .serverNameOrHomeserverUrl(serverNameOrUrl: homeServer)
      .sqliteStore(config: sqliteConfig)
      .withSearchIndexStore(
        path: URL.sessionCaches(for: storeId).appending(component: "SearchIndex")
          .path(percentEncoded: false),
        key: storePassphrase
      )
      .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
      .threadsEnabled(enabled: true, threadSubscriptions: true)
      .autoEnableCrossSigning(autoEnableCrossSigning: true)
      .userAgent(userAgent: "Mactrix macOS")
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
      homeServer: homeServer, storeId: storeID, storePassphrase: storePassphrase
    ).build()

    let details = await client.homeserverLoginDetails()
    return HomeserverLogin(
      storeID: storeID, storePassphrase: storePassphrase, unauthenticatedClient: client,
      loginDetails: details)
  }

  public static func attemptRestore(accountStore: AccountStore = AccountStore()) async throws
    -> MatrixClient?
  {
    try accountStore.migrateLegacyIfNeeded()
    let sessions = try accountStore.loadAll()
    guard
      let userSession = sessions.first(where: { $0.storeID == accountStore.activeStoreID })
        ?? sessions.first
    else { return nil }

    return try await MatrixClient(userSession: userSession, accountStore: accountStore)
  }

  public func reset() async throws {
    recentReactions.invalidate()
    isResettingSession = true
    await roomSubscriptions.invalidate()
    Logger.matrixClient.debug("matrix client sign out")
    try? await client.logout()
    try? FileManager.default.removeItem(at: .sessionData(for: storeID))
    try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
    try accountStore.remove(storeID: storeID)
    Logger.matrixClient.debug("matrix client sign out complete")
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

  public func startSync() async throws {
    let _syncService = try await client.syncService().withOfflineMode().finish()
    syncService = _syncService

    syncStateHandle = _syncService.state(listener: self)

    let _roomListService = _syncService.roomListService()
    roomListService = _roomListService
    roomListServiceStateHandle = _roomListService.state(listener: self)
    syncIndicatorHandle = _roomListService.syncIndicator(
      delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: self)

    let roomEntriesListener = AsyncSDKListener<[RoomListEntriesUpdate]>()
    let _roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(
      pageSize: 100, listener: roomEntriesListener)
    _ = _roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))
    roomListEntriesHandle = _roomListEntriesHandle

    Task { [weak self] in
      for await roomEntries in roomEntriesListener {
        guard let self else { break }
        self.updateRoomEntries(roomEntriesUpdate: roomEntries)
      }
    }

    notificationClient = try await client.notificationClient(
      processSetup: .singleProcess(syncService: _syncService))
    await client.registerNotificationHandler(listener: notifications)

    try await client.getSessionVerificationController().setDelegate(delegate: self)

    let encryption = client.encryption()
    verificationStateHandle = encryption.verificationStateListener(listener: self)
    recoveryStateHandle = encryption.recoveryStateListener(listener: self)
    backupStateHandle = encryption.backupStateListener(listener: self)

    ignoredUsersHandle = client.subscribeToIgnoredUsers(listener: self)
    ignoredUserIds = try await client.ignoredUsers()

    // Start the sync loop.
    await _syncService.start()
    Logger.matrixClient.info("Matrix sync started")
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
    Logger.matrixClient.debug("client session delegate: save session in keychain")
    do {
      try accountStore.save(
        UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase))
    } catch {
      Logger.matrixClient.error("failed to save session in keychain: \(error)")
    }
  }
}

extension URL {
  fileprivate static func sessionData(for sessionID: String) -> URL {
    applicationSupportDirectory
      .appending(component: "dk.qpqp.mactrix")
      .appending(component: sessionID)
  }

  fileprivate static func sessionCaches(for sessionID: String) -> URL {
    cachesDirectory
      .appending(component: "dk.qpqp.mactrix")
      .appending(component: sessionID)
  }
}

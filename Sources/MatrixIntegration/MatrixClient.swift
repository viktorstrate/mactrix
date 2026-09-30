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
  private let storePassphrase: String
  public internal(set) var client: ClientProtocol!

  public internal(set) var rooms: [SidebarRoom] = []

  public internal(set) var spaceService: LiveSpaceService!

  private var clientDelegateHandle: TaskHandle?
  public internal(set) var authenticationFailed: Bool = false

  public let notifications: MatrixNotifications = .init()

  init(userSession: UserSession) async throws {
    storeID = userSession.storeID
    storePassphrase = userSession.storePassphrase

    client = try await Self.clientBuilder(
      homeServer: userSession.homeserverURL, storeId: storeID, storePassphrase: storePassphrase
    )
    // .enableOidcRefreshLock()
    .setSessionDelegate(sessionDelegate: self)
    .build()

    spaceService = LiveSpaceService(spaceService: await client.spaceService())
    clientDelegateHandle = try? client.setDelegate(delegate: self)
  }

  init(storeID: String, storePassphrase: String, client: ClientProtocol) async {
    self.storeID = storeID
    self.storePassphrase = storePassphrase
    self.client = client

    spaceService = LiveSpaceService(spaceService: await client.spaceService())
    clientDelegateHandle = try? self.client.setDelegate(delegate: self)
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

  public static func attemptRestore() async throws -> MatrixClient? {
    guard let userSession = try UserSession.loadUserFromKeychain() else { return nil }

    let matrixClient = try await MatrixClient(userSession: userSession)

    // Restore the client using the session.
    try await matrixClient.client.restoreSession(session: userSession.session)

    return matrixClient
  }

  public func reset() async throws {
    Logger.matrixClient.debug("matrix client sign out")
    try? await client.logout()
    try? FileManager.default.removeItem(at: .sessionData(for: storeID))
    try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
    try AppKeychain().removeAll()
    Logger.matrixClient.debug("matrix client sign out complete")
  }

  public internal(set) var syncService: SyncService?
  public internal(set) var syncState: SyncServiceState = .terminated
  public internal(set) var roomListService: RoomListService?
  public internal(set) var roomListServiceState: RoomListServiceState?
  public internal(set) var showRoomSyncIndicator: RoomListServiceSyncIndicator?
  public internal(set) var ignoredUserIds: [String] = []

  @ObservationIgnored fileprivate var roomListEntriesHandle:
    RoomListEntriesWithDynamicAdaptersResult?
  @ObservationIgnored fileprivate var roomListServiceStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var syncIndicatorHandle: TaskHandle?
  @ObservationIgnored fileprivate var syncStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var verificationStateHandle: TaskHandle?
  @ObservationIgnored fileprivate var ignoredUsersHandle: TaskHandle?

  /// The latest session verification request received by another client
  public var sessionVerificationRequest: SessionVerificationRequestDetails?
  public var sessionVerificationData: SessionVerificationData?
  public var verificationState: VerificationState?

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

    verificationStateHandle = client.encryption().verificationStateListener(listener: self)

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

enum MatrixClientRestoreSessionError: Error {
  case sessionNotFound, wrongUserId
}

extension MatrixClient: MatrixRustSDK.ClientSessionDelegate {
  public nonisolated func retrieveSessionFromKeychain(userId: String) throws
    -> MatrixRustSDK.Session
  {
    Logger.matrixClient.debug(
      "client session delegate: retrieve session from keychain: \(userId, privacy: .sensitive)")

    let userSession = try UserSession.loadUserFromKeychain()
    if let userSession {
      if userSession.userID == userId {
        return userSession.session
      } else {
        Logger.matrixClient.debug(
          "restored user session has wrong userId: \(userSession.userID, privacy: .sensitive), expected \(userId, privacy: .sensitive)"
        )
        throw MatrixClientRestoreSessionError.wrongUserId
      }
    } else {
      throw MatrixClientRestoreSessionError.sessionNotFound
    }
  }

  public nonisolated func saveSessionInKeychain(session: MatrixRustSDK.Session) {
    Logger.matrixClient.debug("client session delegate: save session in keychain")
    do {
      try UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase)
        .saveUserToKeychain()
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

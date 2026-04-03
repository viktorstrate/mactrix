import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Security
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

@MainActor @Observable
class MatrixClient {
    let storeID: String
    let storePassphrase: String
    var client: ClientProtocol!

    var rooms: [SidebarRoom] = []

    var spaceService: LiveSpaceService!

    private var clientDelegateHandle: TaskHandle?
    var authenticationFailed: Bool = false

    let notifications: MatrixNotifications = .init()

    init(userSession: UserSession) async throws {
        storeID = userSession.storeID
        storePassphrase = userSession.storePassphrase

        client = try await Self.clientBuilder(homeServer: userSession.homeserverURL, storeId: storeID, storePassphrase: storePassphrase)
            //.enableOidcRefreshLock()
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
        return try UserSession(session: client.session(), storeID: storeID, storePassphrase: storePassphrase)
    }

    static func clientBuilder(homeServer: String, storeId: String, storePassphrase: String) -> ClientBuilder {
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
        var result = [UInt8](repeating: UInt8.random(in: 0 ..< UInt8.max), count: 32)
        let status = unsafe SecRandomCopyBytes(kSecRandomDefault, result.count, &result)
        if status != errSecSuccess {
            throw SecureRandomBytesError(code: status)
        }

        return Data(result).base64EncodedString()
    }

    static func loginDetails(homeServer: String) async throws -> HomeserverLogin {
        let storeID = UUID().uuidString
        let storePassphrase = try Self.generateStorePassphrase()

        let client = try await Self.clientBuilder(homeServer: homeServer, storeId: storeID, storePassphrase: storePassphrase).build()

        let details = await client.homeserverLoginDetails()
        return HomeserverLogin(storeID: storeID, storePassphrase: storePassphrase, unauthenticatedClient: client, loginDetails: details)
    }

    static func attemptRestore() async throws -> MatrixClient? {
        guard let userSession = try UserSession.loadUserFromKeychain() else { return nil }

        let matrixClient = try await MatrixClient(userSession: userSession)

        // Restore the client using the session.
        try await matrixClient.client.restoreSession(session: userSession.session)

        return matrixClient
    }

    func reset() async throws {
        Logger.matrixClient.debug("matrix client sign out")
        try? await client.logout()
        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
        try AppKeychain().removeAll()
        Logger.matrixClient.debug("matrix client sign out complete")
    }

    var syncService: SyncService?
    var syncState: SyncServiceState = .terminated
    var roomListService: RoomListService?
    var roomListServiceState: RoomListServiceState?
    var showRoomSyncIndicator: RoomListServiceSyncIndicator?
    var ignoredUserIds: [String] = []

    @ObservationIgnored fileprivate var roomListEntriesHandle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored fileprivate var roomListServiceStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncIndicatorHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var verificationStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var ignoredUsersHandle: TaskHandle?

    /// The latest session verification request received by another client
    var sessionVerificationRequest: SessionVerificationRequestDetails?
    var sessionVerificationData: SessionVerificationData?
    var verificationState: VerificationState?

    var notificationClient: NotificationClient?

    func startSync() async throws {
        let _syncService = try await client.syncService().withOfflineMode().finish()
        syncService = _syncService

        syncStateHandle = _syncService.state(listener: self)

        let _roomListService = _syncService.roomListService()
        roomListService = _roomListService
        roomListServiceStateHandle = _roomListService.state(listener: self)
        syncIndicatorHandle = _roomListService.syncIndicator(delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: self)

        let roomEntriesListener = AsyncSDKListener<[RoomListEntriesUpdate]>()
        let _roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: roomEntriesListener)
        _ = _roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))
        roomListEntriesHandle = _roomListEntriesHandle

        Task { [weak self] in
            let throttledListener = roomEntriesListener
                ._throttle(for: .milliseconds(500), reducing: { result, next in
                    (result ?? []) + next
                })

            for await roomEntries in throttledListener {
                guard let self else { break }
                self.updateRoomEntries(roomEntriesUpdate: roomEntries)
            }
        }

        notificationClient = try await client.notificationClient(processSetup: .singleProcess(syncService: _syncService))
        await client.registerNotificationHandler(listener: notifications)

        try await client.getSessionVerificationController().setDelegate(delegate: self)

        verificationStateHandle = client.encryption().verificationStateListener(listener: self)

        ignoredUsersHandle = client.subscribeToIgnoredUsers(listener: self)
        ignoredUserIds = try await client.ignoredUsers()

        // Start the sync loop.
        await _syncService.start()
        Logger.matrixClient.info("Matrix sync started")
    }

    func clearCache() async throws {
        try await client.clearCaches(syncService: syncService)
    }

    func isUserIgnored(_ userId: String) -> Bool {
        ignoredUserIds.contains(userId)
    }

    func declineVerificationRequest(request: SessionVerificationRequestDetails) async throws {
        try await client.getSessionVerificationController().acknowledgeVerificationRequest(
            senderId: request.senderProfile.userId, flowId: request.flowId
        )

        try await client.getSessionVerificationController().cancelVerification()
    }

    func acceptVerificationRequest(request: SessionVerificationRequestDetails) async throws {
        try await client.getSessionVerificationController().acknowledgeVerificationRequest(
            senderId: request.senderProfile.userId, flowId: request.flowId
        )

        try await client.getSessionVerificationController().acceptVerificationRequest()
    }

    func requestDeviceVerification() async throws {
        try await client.getSessionVerificationController().requestDeviceVerification()
    }
}

enum MatrixClientRestoreSessionError: Error {
    case sessionNotFound, wrongUserId
}

extension MatrixClient: MatrixRustSDK.ClientSessionDelegate {
    nonisolated func retrieveSessionFromKeychain(userId: String) throws -> MatrixRustSDK.Session {
        Logger.matrixClient.debug("client session delegate: retrieve session from keychain: \(userId, privacy: .sensitive)")

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

    nonisolated func saveSessionInKeychain(session: MatrixRustSDK.Session) {
        Logger.matrixClient.debug("client session delegate: save session in keychain")
        do {
            try UserSession(session: session, storeID: storeID, storePassphrase: storePassphrase).saveUserToKeychain()
        } catch {
            Logger.matrixClient.error("failed to save session in keychain: \(error)")
        }
    }
}

extension MatrixClient: UI.ImageLoader {
    static let imageCache = NSCache<NSString, NSImage>()

    func cachedImage(matrixUrl: String) -> Image? {
        guard let nsImage = Self.imageCache.object(forKey: NSString(string: matrixUrl)) else { return nil }
        return Image(nsImage: nsImage)
    }

    func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image? {
        let cacheKey: NSString = if let size {
            NSString(string: "\(matrixUrl)_\(Int(size.width))x\(Int(size.height))")
        } else {
            NSString(string: matrixUrl)
        }
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return Image(nsImage: cached)
        }

        let mediaSource = try MediaSource.fromUrl(url: matrixUrl)

        let imageData: Data
        if let size {
            let width = UInt64(size.width)
            let height = UInt64(size.height)
            imageData = try await client.getMediaThumbnail(mediaSource: mediaSource, width: width, height: height)
        } else {
            imageData = try await client.getMediaContent(mediaSource: mediaSource)
        }

        do {
            let nsImage = try imageData.toOrientedImage(contentType: imageData.computeMimeType())
            Self.imageCache.setObject(nsImage, forKey: cacheKey, cost: imageData.count)
            return Image(nsImage: nsImage)
        } catch {
            Logger.matrixClient.error("failed convert matrix media data to Image: \(error) \(imageData)")
            throw error
        }
    }
}

extension MatrixClient {
    struct MatrixClientUserProfileActions: UserProfileActions {
        let userId: String
        let matrixClient: MatrixClient
        let windowState: WindowState

        func sendMessage() async {
            do {
                if let room = try matrixClient.client.getDmRoom(userId: userId) {
                    windowState.selectedRoomId = room.id
                    return
                }

                let createRoomParams = CreateRoomParameters(
                    name: nil, isEncrypted: false, isDirect: true, visibility: .private,
                    preset: .privateChat, invite: [userId]
                )
                let roomId = try await matrixClient.client.createRoom(request: createRoomParams)
                windowState.selectedRoomId = roomId
            } catch {
                Logger.viewCycle.error("failed to get DM room for user \(userId): \(error)")
            }
        }

        func shareProfile() {}

        func ignoreUser() async {
            Logger.viewCycle.info("Ignore user \(userId)")
            do {
                try await matrixClient.client.ignoreUser(userId: userId)
            } catch {
                Logger.viewCycle.error("failed to ignore user: \(error)")
            }
        }

        func unignoreUser() async {
            Logger.viewCycle.info("Unignore user \(userId)")
            do {
                try await matrixClient.client.unignoreUser(userId: userId)
            } catch {
                Logger.viewCycle.error("failed to unignore user: \(error)")
            }
        }
    }

    func userProfileActions(forUserId userId: String, windowState: WindowState) -> some UserProfileActions {
        return MatrixClientUserProfileActions(userId: userId, matrixClient: self, windowState: windowState)
    }
}

extension MatrixClient {
    @MainActor
    struct MatrixClientRoomPreviewActions: @MainActor RoomPreviewActions {
        let roomId: String
        let matrixClient: MatrixClient
        let windowState: WindowState

        func joinRoom() async throws {
            let room = try await matrixClient.client.joinRoomById(roomId: roomId)
            let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
            windowState.selectedScreen = .joinedRoom(timeline: timeline)
        }

        func knockRoom() async throws {
            let room = try await matrixClient.client.knock(roomIdOrAlias: roomId, reason: nil, serverNames: ["matrix.org"])
            let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
            windowState.selectedScreen = .joinedRoom(timeline: timeline)
        }

        func visitRoom() {
            windowState.selectedRoomId = roomId
        }
    }

    func roomPreviewActions(forRoomWithId roomId: String, windowState: WindowState) -> RoomPreviewActions {
        return MatrixClientRoomPreviewActions(roomId: roomId, matrixClient: self, windowState: windowState)
    }
}

private extension URL {
    static func sessionData(for sessionID: String) -> URL {
        applicationSupportDirectory
            .appending(component: applicationID)
            .appending(component: sessionID)
    }

    static func sessionCaches(for sessionID: String) -> URL {
        cachesDirectory
            .appending(component: applicationID)
            .appending(component: sessionID)
    }
}

import Foundation
import KeychainAccess
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

struct UserSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let userID: String
    let deviceID: String
    let homeserverURL: String
    let oidcData: String?
    let storeID: String

    init(session: Session, storeID: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userID = session.userId
        deviceID = session.deviceId
        homeserverURL = session.homeserverUrl
        oidcData = session.oidcData
        self.storeID = storeID
    }

    var session: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userID,
                deviceId: deviceID,
                homeserverUrl: homeserverURL,
                oidcData: oidcData,
                slidingSyncVersion: .native)
    }

    fileprivate static var keychainKey: String { "UserSession" }

    func saveUserToKeychain() throws {
        let keychainData = try JSONEncoder().encode(self)
        let keychain = Keychain(service: applicationID)
        try keychain.set(keychainData, key: Self.keychainKey)
    }

    static func loadUserFromKeychain() throws -> Self? {
        Logger.matrixClient.debug("Load user from keychain")
        /* #if DEBUG
             if true {
                 return try JSONDecoder().decode(Self.self, from: DevSecrets.matrixSession.data(using: .utf8)!)
             }
         #endif */
        let keychain = Keychain(service: applicationID)
        guard let keychainData = try keychain.getData(keychainKey) else { return nil }
        return try JSONDecoder().decode(Self.self, from: keychainData)
    }
}

enum SelectedScreen {
    case joinedRoom(timeline: LiveTimeline)
    case loadMatrixUrl(_ url: Utils.MatrixUriScheme)
    case previewRoom(_ room: RoomPreview)
    case user(profile: UserProfile)
    case newRoom
    case none
}

@MainActor @Observable
class MatrixClient {
    let storeID: String
    var client: ClientProtocol!

    var rooms: [SidebarRoom] = []

    var spaceService: LiveSpaceService!

    private var clientDelegateListener: MatrixRustListener<ClientDelegateEvent>?
    var authenticationFailed: Bool = false

    let notifications: MatrixNotifications = .init()

    init(storeID: String, clientBuilder: ClientBuilderProtocol) async throws {
        self.storeID = storeID

        client = try await clientBuilder
            .enableOidcRefreshLock()
            .setSessionDelegate(sessionDelegate: MatrixClientSessionDelegate(storeID: storeID))
            .build()

        spaceService = LiveSpaceService(spaceService: await client.spaceService())

        configureClientDelegate()
    }

    init(storeID: String, client: ClientProtocol) async {
        self.storeID = storeID
        self.client = client
        spaceService = LiveSpaceService(spaceService: await client.spaceService())

        configureClientDelegate()
    }

    private func configureClientDelegate() {
        clientDelegateListener = MatrixRustListener(
            configure: { continuation in
                let delegate = AnonymousClientDelegate { event in
                    continuation.yield(event)
                }

                do {
                    return try self.client.setDelegate(delegate: delegate)
                } catch {
                    Logger.matrixClient.error("Failed to set client delegate: \(error)")
                    return nil
                }
            },
            onElement: { [weak self] event in
                guard let self else { return }

                switch event {
                case let .didReceiveAuthError(isSoftLogout: isSoftLogout):
                    Logger.matrixClient.debug("did receive auth error: soft logout \(isSoftLogout, privacy: .public)")
                    if !isSoftLogout {
                        authenticationFailed = true
                    }
                }
            }
        )
    }

    func userSession() throws -> UserSession {
        return try UserSession(session: client.session(), storeID: storeID)
    }

    static func clientBuilder(homeServer: String, storeId: String) -> ClientBuilder {
        return ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeServer)
            .sessionPaths(dataPath: URL.sessionData(for: storeId).path(percentEncoded: false),
                          cachePath: URL.sessionCaches(for: storeId).path(percentEncoded: false))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .threadsEnabled(enabled: true, threadSubscriptions: true)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .userAgent(userAgent: "Mactrix macOS")
    }

    static func loginDetails(homeServer: String) async throws -> HomeserverLogin {
        let storeID = UUID().uuidString

        let client = try await Self.clientBuilder(homeServer: homeServer, storeId: storeID).build()

        let details = await client.homeserverLoginDetails()
        return HomeserverLogin(storeID: storeID, unauthenticatedClient: client, loginDetails: details)
    }

    static func attemptRestore() async throws -> MatrixClient? {
        guard let userSession = try UserSession.loadUserFromKeychain() else { return nil }

        let session = userSession.session
        let storeID = userSession.storeID

        // Build a client for the homeserver.
        let clientBuilder = Self.clientBuilder(homeServer: session.homeserverUrl, storeId: storeID)

        let matrixClient = try await MatrixClient(storeID: storeID, clientBuilder: clientBuilder)

        // Restore the client using the session.
        try await matrixClient.client.restoreSession(session: session)

        return matrixClient
    }

    func reset() async throws {
        Logger.matrixClient.debug("matrix client sign out")
        try? await client.logout()
        try? FileManager.default.removeItem(at: .sessionData(for: storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: storeID))
        let keychain = Keychain(service: applicationID)
        try keychain.removeAll()
        Logger.matrixClient.debug("matrix client sign out complete")
    }

    var syncService: SyncService?
    var syncState: SyncServiceState = .terminated
    var roomListService: RoomListService?
    var roomListServiceState: RoomListServiceState?
    var showRoomSyncIndicator: RoomListServiceSyncIndicator?
    var ignoredUserIds: [String] = []

    @ObservationIgnored private var roomListEntriesListener: MatrixRustListener<[RoomListEntriesUpdate]>?
    @ObservationIgnored private var roomListServiceStateListener: MatrixRustListener<RoomListServiceState>?
    @ObservationIgnored private var syncIndicatorListener: MatrixRustListener<RoomListServiceSyncIndicator>?
    @ObservationIgnored private var syncStateListener: MatrixRustListener<SyncServiceState>?
    @ObservationIgnored private var verificationStateListener: MatrixRustListener<VerificationState>?
    @ObservationIgnored private var ignoredUsersListener: MatrixRustListener<[String]>?

    /// The latest session verification request received by another client
    var sessionVerificationRequest: SessionVerificationRequestDetails?
    var sessionVerificationData: SessionVerificationData?
    var verificationState: VerificationState?

    var notificationClient: NotificationClient?

    func startSync() async throws {
        let _syncService = try await client.syncService().withOfflineMode().finish()
        syncService = _syncService

        syncStateListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousSyncServiceStateObserver { state in
                    continuation.yield(state)
                }
                return _syncService.state(listener: listener)
            },
            onElement: { [weak self] state in
                self?.syncState = state
            }
        )

        let _roomListService = _syncService.roomListService()
        roomListService = _roomListService

        roomListServiceStateListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousRoomListServiceStateListener { state in
                    continuation.yield(state)
                }
                return _roomListService.state(listener: listener)
            },
            onElement: { [weak self] state in
                self?.roomListServiceState = state
            }
        )

        syncIndicatorListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousRoomListServiceSyncIndicatorListener { syncIndicator in
                    continuation.yield(syncIndicator)
                }
                return _roomListService.syncIndicator(delayBeforeShowingInMs: 200, delayBeforeHidingInMs: 200, listener: listener)
            },
            onElement: { [weak self] syncIndicator in
                self?.showRoomSyncIndicator = syncIndicator
            }
        )

        roomListEntriesListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousRoomListEntriesListener { roomEntriesUpdate in
                    continuation.yield(roomEntriesUpdate)
                }

                do {
                    let roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: listener)
                    _ = roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))

                    return roomListEntriesHandle.entriesStream()
                } catch {
                    Logger.matrixClient.error("Failed to register room list entries listener: \(error)")
                    return nil
                }
            },
            onElement: { [weak self] roomEntriesUpdate in
                guard let self else { return }

                for update in roomEntriesUpdate {
                    switch update {
                    case let .append(values):
                        rooms.append(contentsOf: values.map(SidebarRoom.init(room:)))
                    case .clear:
                        rooms.removeAll()
                    case let .pushFront(room):
                        rooms.insert(SidebarRoom(room: room), at: 0)
                    case let .pushBack(room):
                        rooms.append(SidebarRoom(room: room))
                    case .popFront:
                        rooms.removeFirst()
                    case .popBack:
                        rooms.removeLast()
                    case let .insert(index, room):
                        rooms.insert(SidebarRoom(room: room), at: Int(index))
                    case let .set(index, room):
                        rooms[Int(index)] = SidebarRoom(room: room)
                    case let .remove(index):
                        rooms.remove(at: Int(index))
                    case let .truncate(length):
                        rooms.removeSubrange(Int(length) ..< rooms.count)
                    case let .reset(values: values):
                        rooms = values.map(SidebarRoom.init(room:))
                    }
                }
            }
        )

        notificationClient = try await client.notificationClient(processSetup: .singleProcess(syncService: _syncService))
        await client.registerNotificationHandler(listener: notifications)

        try await client.getSessionVerificationController().setDelegate(delegate: self)

        verificationStateListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousVerificationStateListener { status in
                    continuation.yield(status)
                }
                return self.client.encryption().verificationStateListener(listener: listener)
            },
            onElement: { [weak self] status in
                self?.verificationState = status
            }
        )

        ignoredUsersListener = MatrixRustListener(
            configure: { continuation in
                do {
                    self.ignoredUserIds = try await self.client.ignoredUsers()
                } catch {
                    Logger.matrixClient.error("Failed to load ignored users on start: \(error)")
                }

                let listener = AnonymousIgnoredUsersListener { ignoredUserIds in
                    continuation.yield(ignoredUserIds)
                }
                return self.client.subscribeToIgnoredUsers(listener: listener)
            },
            onElement: { [weak self] ignoredUserIds in
                guard let self else { return }
                Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
                self.ignoredUserIds = ignoredUserIds
            }
        )

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

extension MatrixClient: UI.ImageLoader {
    func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image? {
        let imageData: Data
        if let size {
            let width = UInt64(size.width)
            let height = UInt64(size.height)
            imageData = try await client.getMediaThumbnail(mediaSource: .fromUrl(url: matrixUrl), width: UInt64(width), height: UInt64(height))
        } else {
            imageData = try await client.getMediaContent(mediaSource: .fromUrl(url: matrixUrl))
        }

        do {
            return try await Image(importing: imageData, contentType: imageData.computeMimeType())
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

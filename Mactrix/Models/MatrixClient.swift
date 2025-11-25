import Foundation
import KeychainAccess
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import UniformTypeIdentifiers

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
    case previewRoom(_ room: RoomPreview)
    case newRoom
    case none
}

@MainActor
@Observable class MatrixClient {
    let storeID: String
    var client: ClientProtocol!

    var rooms: [SidebarRoom] = []

    var spaceService: LiveSpaceService!

    private var clientDelegateHandle: TaskHandle?
    var authenticationFailed: Bool = false

    init(storeID: String, clientBuilder: ClientBuilderProtocol) async throws {
        self.storeID = storeID

        client = try await clientBuilder
            .enableOidcRefreshLock()
            .setSessionDelegate(sessionDelegate: self)
            .build()

        spaceService = LiveSpaceService(spaceService: client.spaceService())

        clientDelegateHandle = try? client.setDelegate(delegate: self)
    }

    init(storeID: String, client: ClientProtocol) {
        self.storeID = storeID
        self.client = client
        spaceService = LiveSpaceService(spaceService: client.spaceService())

        clientDelegateHandle = try? self.client.setDelegate(delegate: self)
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

    @ObservationIgnored fileprivate var roomListEntriesHandle: RoomListEntriesWithDynamicAdaptersResult?
    @ObservationIgnored fileprivate var roomListServiceStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncIndicatorHandle: TaskHandle?
    @ObservationIgnored fileprivate var syncStateHandle: TaskHandle?
    @ObservationIgnored fileprivate var verificationStateHandle: TaskHandle?

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

        let _roomListEntriesHandle = try await _roomListService.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: self)
        roomListEntriesHandle = _roomListEntriesHandle

        _ = _roomListEntriesHandle.controller().setFilter(kind: .all(filters: []))

        notificationClient = try await client.notificationClient(processSetup: .singleProcess(syncService: _syncService))

        try await client.getSessionVerificationController().setDelegate(delegate: self)

        verificationStateHandle = client.encryption().verificationStateListener(listener: self)

        // Start the sync loop.
        await _syncService.start()
        Logger.matrixClient.info("Matrix sync started")
    }

    func clearCache() async throws {
        try await client.clearCaches(syncService: syncService)
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

extension MatrixClient: @MainActor MatrixRustSDK.ClientSessionDelegate {
    func retrieveSessionFromKeychain(userId: String) throws -> MatrixRustSDK.Session {
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

    func saveSessionInKeychain(session: MatrixRustSDK.Session) {
        Logger.matrixClient.debug("client session delegate: save session in keychain")
        do {
            try UserSession(session: session, storeID: storeID).saveUserToKeychain()
        } catch {
            Logger.matrixClient.error("failed to save session in keychain: \(error)")
        }
    }
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

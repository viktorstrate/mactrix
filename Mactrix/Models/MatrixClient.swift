import Foundation
import MatrixRustSDK
import KeychainAccess

struct UserSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let userID: String
    let deviceID: String
    let homeserverURL: String
    let oidcData: String?
    let storeID: String
    
    init(session: Session, storeID: String) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        self.userID = session.userId
        self.deviceID = session.deviceId
        self.homeserverURL = session.homeserverUrl
        self.oidcData = session.oidcData
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
        #if DEBUG
        if true {
            return try JSONDecoder().decode(Self.self, from: DevSecrets.matrixSession.data(using: .utf8)!)
        }
        #endif
        let keychain = Keychain(service: applicationID)
        guard let keychainData = try keychain.getData(keychainKey) else { return nil }
        return try JSONDecoder().decode(Self.self, from: keychainData)
    }
}

@Observable class MatrixClient {
    let storeID: String
    let client: ClientProtocol
    
    var rooms: [Room] = []
    
    init(storeID: String, client: ClientProtocol) {
        self.storeID = storeID
        self.client = client
    }
    
    static var previewMock: MatrixClient {
        MatrixClient(storeID: UUID().uuidString, client: MatrixClientMock())
    }
    
    func userSession() throws -> UserSession {
        return UserSession(session: try client.session(), storeID: storeID)
    }
    
    static func login(homeServer: String, username: String, password: String) async throws -> MatrixClient {
        let storeID = UUID().uuidString
        
        // Create a client for a particular homeserver.
        // Note that we can pass a server name (the second part of a Matrix user ID) instead of the direct URL.
        // This allows the SDK to discover the homeserver's well-known configuration for Sliding Sync support.
        let client = try await ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeServer)
            .sessionPaths(dataPath: URL.sessionData(for: storeID).path(percentEncoded: false),
                          cachePath: URL.sessionCaches(for: storeID).path(percentEncoded: false))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .build()
        
        // Login using password authentication.
        try await client.login(username: username, password: password, initialDeviceName: "Mactrix", deviceId: nil)
        
        let matrixClient = MatrixClient(storeID: storeID, client: client)
        
        let userSession = try matrixClient.userSession()
        try userSession.saveUserToKeychain()
        
        return matrixClient
    }
    
    static func attemptRestore() async throws -> MatrixClient? {
        guard let userSession = try UserSession.loadUserFromKeychain() else { return nil }
        
        let session = userSession.session
        let storeID = userSession.storeID
        
        // Build a client for the homeserver.
        let client = try await ClientBuilder()
            .sessionPaths(dataPath: URL.sessionData(for: storeID).path(percentEncoded: false),
                          cachePath: URL.sessionCaches(for: storeID).path(percentEncoded: false))
            .homeserverUrl(url: session.homeserverUrl)
            .build()
        
        // Restore the client using the session.
        try await client.restoreSession(session: session)
        
        return MatrixClient(storeID: storeID, client: client)
    }
    
    func reset() async throws {
        try? await client.logout()
        try? FileManager.default.removeItem(at: .sessionData(for: self.storeID))
        try? FileManager.default.removeItem(at: .sessionCaches(for: self.storeID))
        let keychain = Keychain(service: applicationID)
        try keychain.removeAll()
    }
    
    var syncService: SyncService?
    var roomListService: RoomListService?
    var roomListEntriesHandle: RoomListEntriesWithDynamicAdaptersResult?
    
    func startSync() async throws {
        syncService = try await client.syncService().finish()
        roomListService = syncService?.roomListService()
        roomListEntriesHandle = try await roomListService?.allRooms().entriesWithDynamicAdapters(pageSize: 100, listener: self)
        let _ = roomListEntriesHandle?.controller().setFilter(kind: .all(filters: []))
        
        // Start the sync loop.
        await syncService?.start()
        print("Matrix sync started")
    }
    
    func clearCache() async throws {
        try await self.client.clearCaches(syncService: syncService)
    }
}

fileprivate extension URL {
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

import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Security
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
    let oauthData: String?
    let storeID: String
    let storePassphrase: String

    init(session: Session, storeID: String, storePassphrase: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userID = session.userId
        deviceID = session.deviceId
        homeserverURL = session.homeserverUrl
        oauthData = session.oauthData
        self.storeID = storeID
        self.storePassphrase = storePassphrase
    }

    var session: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userID,
                deviceId: deviceID,
                homeserverUrl: homeserverURL,
                oauthData: oauthData,
                slidingSyncVersion: .native)
    }

    fileprivate static var keychainKey: String { "UserSession" }

    func saveUserToKeychain() throws {
        let keychainData = try JSONEncoder().encode(self)
        try AppKeychain().save(keychainData, forKey: Self.keychainKey)
    }

    static func loadUserFromKeychain() throws -> Self? {
        Logger.matrixClient.debug("Load user from keychain")
        if let keychainData = try AppKeychain().load(forKey: keychainKey) {
            return try JSONDecoder().decode(Self.self, from: keychainData)
        }
        return nil
    }
}

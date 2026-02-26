import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

final class MatrixClientSessionDelegate: MatrixRustSDK.ClientSessionDelegate {
    let storeID: String

    init(storeID: String) {
        self.storeID = storeID
    }

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

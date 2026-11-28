import Foundation
import MatrixRustSDK

struct UserSession: Codable, Equatable {
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
    Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userID,
      deviceId: deviceID,
      homeserverUrl: homeserverURL,
      oauthData: oauthData,
      slidingSyncVersion: .native)
  }
}

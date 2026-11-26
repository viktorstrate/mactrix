import MactrixUI
import MatrixProtocols
import MatrixRustSDK
import OSLog
import SwiftUI

struct InspectorUserInfo: View {
  @Environment(WindowState.self) private var windowState

  let userId: String

  @State private var profile: MatrixRustSDK.UserProfile?

  var isUserIgnored: Bool {
    windowState.matrixClient?.ignoredUserIds.contains(userId) == true
  }

  @ViewBuilder
  var content: some View {
    if let profile {
      MactrixUI.UserProfileView(
        profile: profile,
        isUserIgnored: isUserIgnored,
        actions: windowState.matrixClient?.userProfileActions(
          forUserId: userId, windowState: windowState),
        timelineActions: nil,
        imageLoader: windowState.matrixClient
      )
    } else {
      MactrixUI.UserProfileView(
        profile: MockUserProfile(),
        isUserIgnored: isUserIgnored,
        actions: nil,
        timelineActions: nil,
        imageLoader: windowState.matrixClient
      )
      .redacted(reason: .placeholder)
    }
  }

  var body: some View {
    content
      .task(id: userId) {
        guard let matrixClient = windowState.matrixClient else { return }

        do {
          profile = try await matrixClient.client.getProfile(userId: userId)
        } catch {
          Logger.viewCycle.error("failed to get profile \(error)")
        }
      }
  }
}

import MatrixRustSDK
import MatrixProtocols
import OSLog
import SwiftUI
import MactrixUI

struct InspectorUserInfo: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let userId: String

    @State private var profile: MatrixRustSDK.UserProfile?

    var isUserIgnored: Bool {
        appState.matrixClient?.ignoredUserIds.contains(userId) == true
    }

    @ViewBuilder
    var content: some View {
        if let profile {
            MactrixUI.UserProfileView(
                profile: profile,
                isUserIgnored: isUserIgnored,
                actions: appState.matrixClient?.userProfileActions(forUserId: userId, windowState: windowState),
                timelineActions: nil,
                imageLoader: appState.matrixClient
            )
        } else {
            MactrixUI.UserProfileView(
                profile: MockUserProfile(),
                isUserIgnored: isUserIgnored,
                actions: nil,
                timelineActions: nil,
                imageLoader: appState.matrixClient
            )
            .redacted(reason: .placeholder)
        }
    }

    var body: some View {
        content
            .task(id: userId) {
                guard let matrixClient = appState.matrixClient else { return }

                do {
                    profile = try await matrixClient.client.getProfile(userId: userId)
                } catch {
                    Logger.viewCycle.error("failed to get profile \(error)")
                }
            }
    }
}

import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

struct LoadMatrixUriScreen: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    let matrixUri: Utils.MatrixUriScheme

    @ViewBuilder
    var content: some View {
        switch matrixUri.kind {
        case .roomAlias(let alias):
            ProgressView {
                Text("Loading room \(alias)")
            }
        case .roomId(let roomId):
            ProgressView {
                Text("Loading room \(roomId)")
            }
        case .user(let userId):
            ProgressView {
                Text("Loading user \(userId)")
            }
        }
    }

    var body: some View {
        content
            .task(id: matrixUri) {
                Logger.viewCycle.debug("LoadMatrixUriScreen TASK")

                guard let matrixClient = appState.matrixClient else {
                    Logger.viewCycle.warning("Matrix client was nil so could not follow url")
                    return
                }

                switch matrixUri.kind {
                case .roomId(let roomId):
                    Logger.viewCycle.debug("Matrix uri match roomId")
                    Task {
                        do {
                            let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomId(
                                roomId: roomId,
                                viaServers: matrixUri.routingVia
                            )
                            windowState.selectedScreen = .previewRoom(roomPreview)
                        } catch {
                            Logger.viewCycle.error("Failed to get room id from url: \(error)")
                        }
                    }
                case .roomAlias(let alias):
                    Logger.viewCycle.debug("Matrix uri match room alias")
                    Task {
                        do {
                            let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomAlias(roomAlias: alias)
                            windowState.selectedScreen = .previewRoom(roomPreview)
                        } catch {
                            Logger.viewCycle.error("Failed to get room alias from url: \(error)")
                        }
                    }
                case .user(let userId):
                    Logger.viewCycle.debug("Matrix uri match user")
                    Task {
                        do {
                            let userProfile = try await matrixClient.client.getProfile(userId: userId)
                            windowState.selectedScreen = .user(profile: userProfile)
                        } catch {
                            Logger.viewCycle.error("Failed to get user profile from url: \(error)")
                        }
                    }
                }
            }
    }
}

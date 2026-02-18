import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct SearchResolvedRoomInspectorView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State private var roomPreview: MatrixRustSDK.RoomPreview?

    let alias: String
    let resolvedRoom: ResolvedRoomAlias

    var roomActions: RoomPreviewActions? {
        guard let preview = roomPreview else { return nil }
        return appState.matrixClient?.roomPreviewActions(forRoomWithId: preview.info().roomId, windowState: windowState)
    }

    var body: some View {
        Group {
            if let roomPreview {
                UI.RoomPreviewView(
                    preview: roomPreview.info(),
                    imageLoader: appState.matrixClient,
                    actions: roomActions
                )
            } else {
                UI.RoomPreviewView(
                    preview: MockRoomPreviewInfo(),
                    imageLoader: appState.matrixClient,
                    actions: roomActions
                )
                .redacted(reason: .placeholder)
            }
        }
        .task(id: alias, priority: .utility) {
            do {
                let preview = try await appState.matrixClient?.client.getRoomPreviewFromRoomId(roomId: resolvedRoom.roomId, viaServers: resolvedRoom.servers)
                self.roomPreview = preview
            } catch {
                Logger.viewCycle.error("failed to get room preview: \(error)")
            }
        }
    }
}

struct SearchInspectorView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @ViewBuilder
    var viewSelector: some View {
        switch windowState.searchTokens.first {
        case .messages:
            Text("Search messages")
        case .rooms:
            SearchRoomInspectorView()
        case .users:
            SearchUserInspectorView()
        case .spaces:
            Text("Search spaces")
        case let .resolvedRoomAlias(alias: alias, resolvedRoom: resolvedRoom):
            SearchResolvedRoomInspectorView(alias: alias, resolvedRoom: resolvedRoom)
        case let .resolvedRoomId(roomPreview: roomPreview):
            UI.RoomPreviewView(
                preview: roomPreview.info(),
                imageLoader: appState.matrixClient,
                actions: appState.matrixClient?.roomPreviewActions(forRoomWithId: roomPreview.info().roomId, windowState: windowState)
            )
        case let .resolvedUser(profile: userProfile):
            UI.UserProfileView(
                profile: userProfile,
                isUserIgnored: appState.matrixClient?.isUserIgnored(userProfile.userId) == true,
                actions: appState.matrixClient?.userProfileActions(forUserId: userProfile.userId, windowState: windowState),
                timelineActions: nil,
                imageLoader: appState.matrixClient
            )
        case nil:
            ContentUnavailableView("Select a search term", systemImage: "magnifyingglass")
            Text("or enter a room alias or a user id")
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        viewSelector
            .inspectorColumnWidth(min: 300, ideal: 300, max: 600)
    }
}

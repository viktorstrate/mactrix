import MatrixRustSDK
import SwiftUI
import UI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State private var searchText: String = ""

    var favorites: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { $0.roomInfo?.isFavourite == true }
    }

    var directs: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { $0.roomInfo?.isDirect == true }
    }

    var rooms: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { !$0.isSpace() && $0.roomInfo?.isDirect != true }
    }

    var spaces: [SidebarSpaceRoom] {
        appState.matrixClient?.spaceService.spaceRooms ?? []
    }

    var body: some View {
        @Bindable var windowState = windowState

        List(selection: $windowState.selectedRoomId) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { room in
                        UI.RoomRow(
                            title: room.displayName() ?? "Unknown room",
                            avatarUrl: room.avatarUrl(),
                            roomInfo: room.roomInfo,
                            imageLoader: appState.matrixClient,
                            joinRoom: nil
                        )
                        .contextMenu {
                            RoomContextMenu(room: room)
                        }
                    }
                }
            }

            Section("Directs") {
                ForEach(directs) { room in
                    UI.RoomRow(
                        title: room.displayName() ?? "Unknown user",
                        avatarUrl: room.avatarUrl(),
                        roomInfo: room.roomInfo,
                        imageLoader: appState.matrixClient,
                        joinRoom: nil
                    )
                    .contextMenu {
                        RoomContextMenu(room: room)
                    }
                }
            }

            Section("Rooms") {
                ForEach(rooms) { room in
                    UI.RoomRow(
                        title: room.displayName() ?? "Unknown Room",
                        avatarUrl: room.avatarUrl(),
                        roomInfo: room.roomInfo,
                        imageLoader: appState.matrixClient,
                        joinRoom: nil
                    )
                    .contextMenu {
                        RoomContextMenu(room: room)
                    }
                }
            }

            Section("Spaces") {
                ForEach(spaces) { space in
                    SpaceDisclosureGroup(space: space)
                }
            }
        }
        .navigationSplitViewColumnWidth(ideal: 200, max: 400)
    }
}

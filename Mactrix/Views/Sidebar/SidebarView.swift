import MatrixRustSDK
import SwiftUI
import UI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State private var searchText: String = ""

    var organizedRooms: OrganizedRooms {
        appState.matrixClient?.organizedRooms ?? OrganizedRooms(
            favorites: [],
            directs: [],
            rooms: [],
            spaces: []
        )
    }

    var body: some View {
        @Bindable var windowState = windowState

        List(selection: $windowState.selectedRoomId) {
            SidebarSyncStateView()

            SessionVerificationStatusView()

            if !organizedRooms.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(organizedRooms.favorites) { room in
                        UI.RoomRow(
                            title: room.room.displayName() ?? "Unknown room",
                            avatarUrl: room.room.avatarUrl(),
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
                ForEach(organizedRooms.directs) { room in
                    UI.RoomRow(
                        title: room.room.displayName() ?? "Unknown user",
                        avatarUrl: room.room.avatarUrl(),
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
                ForEach(organizedRooms.rooms) { room in
                    UI.RoomRow(
                        title: room.room.displayName() ?? "Unknown Room",
                        avatarUrl: room.room.avatarUrl(),
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
                ForEach(organizedRooms.spaces) { space in
                    SpaceDisclosureGroup(space: space)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: nil)
        .toolbar {
            AppCommands.createRoomButton(windowState: windowState)
        }
    }
}

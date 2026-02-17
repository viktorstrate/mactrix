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
            .filter { room in
                let isDirect = room.roomInfo?.isDirect == true
                let favoriteIDs = Set(favorites.map { $0.id })
                return isDirect && !favoriteIDs.contains(room.id)
            }
    }

    var rooms: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { room in
                let isSpace = room.room.isSpace()
                let isDirect = room.roomInfo?.isDirect == true
                let favoriteIDs = Set(favorites.map(\.id))
                return !isSpace && !isDirect && !favoriteIDs.contains(room.id)
            }
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
                Section("Favorites", isExpanded: $windowState.sidebarSections.favorites) {
                    ForEach(favorites) { room in
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

            Section("Directs", isExpanded: $windowState.sidebarSections.directs) {
                ForEach(directs) { room in
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

            Section("Rooms", isExpanded: $windowState.sidebarSections.rooms) {
                ForEach(rooms) { room in
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

            Section("Spaces", isExpanded: $windowState.sidebarSections.spaces) {
                ForEach(spaces) { space in
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

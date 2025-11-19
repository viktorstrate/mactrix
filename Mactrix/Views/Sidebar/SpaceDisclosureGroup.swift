import MatrixRustSDK
import SwiftUI
import UI

struct SpaceDisclosureGroup: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State var space: SidebarSpaceRoom
    @State private var isExpanded: Bool = false

    var loadingRooms: some View {
        Label {
            Text("Loading rooms")
                .foregroundStyle(.secondary)
        } icon: {
            ProgressView().scaleEffect(0.5)
        }
    }

    var spaceRow: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            switch space.children {
            case .loading:
                loadingRooms
            case let .loaded(children):
                if children.paginationState == .loading {
                    loadingRooms
                } else {
                    ForEach(children.rooms) { room in
                        SpaceDisclosureGroup(space: room)
                    }
                }
            case let .error(error):
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(Color.red)
                    .textSelection(.enabled)
            }
        } label: {
            roomRow
        }
        .task(id: isExpanded) {
            if isExpanded {
                await space.loadChildren()
            }
        }
    }

    var joinRoom: (() async throws -> Void)? {
        if appState.matrixClient?.rooms.contains(where: { $0.id() == space.id }) == false {
            return {
                print("Joining room: \(space.id)")
                guard let matrixClient = appState.matrixClient else { return }
                let room = try await matrixClient.client.joinRoomById(roomId: space.id)
                windowState.selectedScreen = .joinedRoom(LiveRoom(matrixRoom: room))
            }
        }

        return nil
    }

    var joinedRoom: SidebarRoom? {
        return appState.matrixClient?.rooms.first(where: { $0.id() == space.id })
    }

    @ViewBuilder
    var roomRow: some View {
        if let joinedRoom {
            UI.RoomRow(
                title: space.spaceRoom.displayName,
                avatarUrl: space.spaceRoom.avatarUrl,
                roomInfo: joinedRoom.roomInfo,
                imageLoader: appState.matrixClient,
                joinRoom: nil
            )
            .contextMenu {
                RoomContextMenu(room: joinedRoom)
            }
        } else {
            UI.RoomRow(
                title: space.spaceRoom.displayName,
                avatarUrl: space.spaceRoom.avatarUrl,
                roomInfo: nil,
                imageLoader: appState.matrixClient,
                joinRoom: joinRoom
            )
        }
    }

    var body: some View {
        if space.spaceRoom.roomType == .space {
            spaceRow
        } else {
            roomRow
        }
    }
}

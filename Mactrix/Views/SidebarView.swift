import SwiftUI
import MatrixRustSDK
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
            case .loaded(let children):
                if children.paginationState == .loading {
                    loadingRooms
                } else {
                    ForEach(children.rooms) { room in
                        SpaceDisclosureGroup(space: room)
                    }
                }
            case .error(let error):
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
                windowState.selectedRoom = SelectedRoom.joinedRoom(LiveRoom(room: room))
            }
        }
        
        return nil
    }
    
    var roomRow: some View {
        UI.RoomRow(
            title: space.spaceRoom.displayName,
            avatarUrl: space.spaceRoom.avatarUrl,
            imageLoader: appState.matrixClient,
            joinRoom: joinRoom,
            placeholderImageName: "network")
    }
    
    var body: some View {
        if space.spaceRoom.roomType == .space {
            spaceRow
        } else {
            roomRow
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) var appState
    
    @State private var searchText: String = ""
    
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
    
    @Binding var selectedRoomId: String?
    
    var body: some View {
        List(selection: $selectedRoomId) {
            Section("Directs") {
                ForEach(directs) { room in
                    UI.RoomRow(
                        title: room.displayName() ?? "Unknown user",
                        avatarUrl: room.avatarUrl(),
                        imageLoader: appState.matrixClient,
                        joinRoom: nil,
                        placeholderImageName: "person.fill"
                    )
                }
            }
            
            Section("Rooms") {
                ForEach(rooms) { room in
                    UI.RoomRow(
                        title: room.displayName() ?? "Unknown Room",
                        avatarUrl: room.avatarUrl(),
                        imageLoader: appState.matrixClient,
                        joinRoom: nil
                    )
                    .contextMenu {
                        Button {
                            Task {
                                do {
                                    print("leaving room: \(room.id())")
                                    try await room.leave()
                                } catch {
                                    print("failed to leave room: \(error)")
                                }
                            }
                        } label: {
                            Label("Leave room", systemImage: "minus.circle")
                        }
                    }
                }
            }
            
            Section("Spaces") {
                ForEach(spaces) { space in
                    SpaceDisclosureGroup(space: space)
                }
            }
        }
    }
}

#Preview {
    SidebarView(selectedRoomId: .constant(nil))
}

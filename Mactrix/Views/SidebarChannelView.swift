import SwiftUI
import MatrixRustSDK

struct SidebarChannelView: View {
    @Environment(AppState.self) var appState
    
    var rooms: [Room] {
        appState.matrixClient?.rooms ?? []
    }
    
    let selectedCategory: SelectedCategory
    @State private var visibleRooms: [Room]? = nil
    
    var body: some View {
        Group {
            if let visibleRooms = visibleRooms {
                List(visibleRooms) { room in
                    NavigationLink(destination: { ChatView(room: room).id(room.id) }) {
                        HStack(alignment: .center) {
                            RoomIcon()
                                .frame(width: 32, height: 32)
                            
                            VStack(alignment: .leading) {
                                Spacer()
                                Text(room.displayName() ?? "Unknown Room")
                                Spacer()
                            }
                            
                            Spacer()
                        }
                        .frame(height: 48)
                        .listRowSeparator(.visible)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.sidebar)
            } else {
                ProgressView()
            }
        }
        .task(id: selectedCategory) { await updateVisibleRooms() }
        .task(id: rooms) { await updateVisibleRooms() }
    }
    
    func updateVisibleRooms() async {
        switch selectedCategory {
        case .rooms:
            self.visibleRooms = rooms.filter { !$0.isSpace() }
        case .space(let spaceId):
            self.visibleRooms = nil
            let spaceRooms = try! await appState.matrixClient?.client.spaceService().spaceRoomList(spaceId: spaceId)
            let roomIds = spaceRooms?.rooms().map { $0.roomId } ?? []
            self.visibleRooms = rooms.filter { room in roomIds.contains(where: { $0 == room.id() }) }
        }
    }
}

#Preview {
    SidebarChannelView(selectedCategory: .rooms)
}

import MatrixRustSDK
import SwiftUI
import UI

struct InspectorScreen: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @ViewBuilder
    var content: some View {
        @Bindable var windowState = windowState

        if windowState.searchFocused {
            SearchInspectorView()
        } else {
            switch windowState.selectedScreen {
            case let .joinedRoom(room):
                UI.RoomInspectorView(room: room, members: room.fetchedMembers, roomInfo: room.roomInfo, imageLoader: appState.matrixClient, inspectorVisible: $windowState.inspectorVisible)
            case let .previewRoom(room):
                Text("Preview room: \(room.info().name ?? "unknown name")")
            case .none, .newRoom:
                Text("No room selected")
            }
        }
    }

    var body: some View {
        @Bindable var windowState = windowState

        content
            .searchable(text: $windowState.searchQuery, tokens: $windowState.searchTokens, isPresented: $windowState.searchFocused, placement: .automatic, prompt: "Search") { token in
                switch token {
                case .users:
                    Text("Users")
                case .rooms:
                    Text("Public Rooms")
                case .spaces:
                    Text("Public Spaces")
                case .messages:
                    Text("Messages")
                }
            }
            .searchSuggestions {
                if windowState.searchTokens.isEmpty {
                    Label("Users", systemImage: "person").searchCompletion(SearchToken.users)
                    Label("Public Rooms", systemImage: "number").searchCompletion(SearchToken.rooms)
                    Label("Public Spaces", systemImage: "network").searchCompletion(SearchToken.spaces)
                    Label("Messages", systemImage: "magnifyingglass.circle").searchCompletion(SearchToken.messages)
                }
            }
            .toolbar(id: "inspector-toolbar") {
                ToolbarItem(id: "toggle-inspector") {
                    Button {
                        windowState.inspectorVisible.toggle()
                    } label: {
                        Label("Toggle Inspector", systemImage: "info.circle")
                    }
                }
            }
    }
}

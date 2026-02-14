import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct InspectorScreen: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @ViewBuilder
    var content: some View {
        @Bindable var windowState = windowState

        switch windowState.inspectorContent {
        case .search:
            SearchInspectorView()
        case let .focusThread(threadTimeline: thread):
            VStack(spacing: 0) {
                UI.ThreadTimelineHeader {
                    windowState.inspectorVisible = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        windowState.inspectorContent = .roomInfo
                    }
                }
                ChatView(timeline: thread)
            }
            .inspectorColumnWidth(min: 200, ideal: 400, max: nil)
        case .roomInfo:
            switch windowState.selectedScreen {
            case let .joinedRoom(timeline: timeline):
                UI.RoomInspectorView(room: timeline.room, members: timeline.room.members, roomInfo: timeline.room.roomInfo, imageLoader: appState.matrixClient, inspectorVisible: $windowState.inspectorVisible)
            case .none, .newRoom, .previewRoom, .loadMatrixUrl(_), .user(profile: _):
                Text("No room selected")
                    .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
            }
        case let .userInfo(userId: userId):
            InspectorUserInfo(userId: userId)
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        case .roomThreads:
            InspectorThreads()
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        case .roomPins:
            InspectorRoomPins()
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        }
    }

    var body: some View {
        @Bindable var windowState = windowState

        content
            .toolbar {
                Button {
                    windowState.toggleInspector()
                } label: {
                    Label("Toggle Inspector", systemImage: "info.circle")
                }
                .help("Toggle Inspector")
            }
    }
}

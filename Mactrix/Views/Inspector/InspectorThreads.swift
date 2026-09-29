import MatrixRustSDK
import MatrixProtocols
import OSLog
import SwiftUI
import UI

struct InspectorThreads: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State var threads: [String] = []

    var timeline: LiveTimeline? {
        guard case let .joinedRoom(timeline: timeline) = windowState.selectedScreen else {
            return nil
        }

        return timeline
    }

    @ViewBuilder
    var content: some View {
        Text("Threads")
    }

    var body: some View {
        content
            .task(id: timeline?.room.id ?? "") {
                guard let _ = timeline else {
                    threads = []
                    return
                }

                // TODO: Fetch threads when Room::list_threads is added to the FFI
                // timeline.room.room.list_threads(...)
            }
    }
}

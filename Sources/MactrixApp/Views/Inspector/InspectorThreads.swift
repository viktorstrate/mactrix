import MactrixUI
import MatrixIntegration
import MatrixProtocols
import MatrixRustSDK
import OSLog
import SwiftUI

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

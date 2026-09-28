import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(appState: appState, windowState: windowState)
    }

    class Coordinator {
        let appState: AppState
        let windowState: WindowState

        init(appState: AppState, windowState: WindowState) {
            self.appState = appState
            self.windowState = windowState
        }
    }

    func makeNSViewController(context: Context) -> TimelineViewController {
        return TimelineViewController(coordinator: context.coordinator, timeline: timeline)
    }

    func updateNSViewController(_ timelineViewController: TimelineViewController, context: Context) {
        // SDK diff batches update the controller directly through LiveTimeline.
    }
}

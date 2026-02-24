import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    let items: [TimelineItem]

    init(timeline: LiveTimeline, items: [TimelineItem]) {
        self.timeline = timeline
        self.items = items
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
        return TimelineViewController(coordinator: context.coordinator, timeline: timeline, timelineItems: items)
    }

    func updateNSViewController(_ timelineViewController: TimelineViewController, context: Context) {
        timelineViewController.updateTimelineItems(items)
    }
}

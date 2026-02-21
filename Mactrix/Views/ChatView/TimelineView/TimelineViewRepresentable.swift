import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState

    let timeline: LiveTimeline
    let items: [TimelineItem]

    init(timeline: LiveTimeline, items: [TimelineItem]) {
        self.timeline = timeline
        self.items = items
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(appState: appState)
    }

    class Coordinator {
        let appState: AppState

        init(appState: AppState) {
            self.appState = appState
        }
    }

    func makeNSViewController(context: Context) -> TimelineViewController {
        return TimelineViewController(coordinator: context.coordinator, timeline: timeline, timelineItems: items)
    }

    func updateNSViewController(_ timelineViewController: TimelineViewController, context: Context) {
        timelineViewController.updateTimelineItems(items)
    }
}

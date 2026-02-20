import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    let timelineItems: [TimelineItem]

    init(timelineItems: [TimelineItem]) {
        self.timelineItems = timelineItems
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    class Coordinator {}

    func makeNSViewController(context: Context) -> TimelineViewController {
        return TimelineViewController(coordinator: context.coordinator, timelineItems: timelineItems)
    }

    func updateNSViewController(_ timelineViewController: TimelineViewController, context: Context) {
        timelineViewController.updateTimelineItems(timelineItems)
    }
}

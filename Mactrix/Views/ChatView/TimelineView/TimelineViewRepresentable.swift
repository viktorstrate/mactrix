import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    class Coordinator {}

    func makeNSViewController(context: Context) -> TimelineViewController {
        return TimelineViewController(coordinator: context.coordinator)
    }

    func updateNSViewController(_ nsViewController: TimelineViewController, context: Context) {}
}

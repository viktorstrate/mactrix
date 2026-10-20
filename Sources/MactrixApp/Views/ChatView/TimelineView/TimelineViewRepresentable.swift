import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
  @AppStorage("fontSize") private var fontSize: Int = 13
  @Environment(AppState.self) private var appState
  @Environment(WindowState.self) private var windowState

  let timeline: LiveTimeline
  let composer: ChatComposerState

  init(timeline: LiveTimeline, composer: ChatComposerState) {
    self.timeline = timeline
    self.composer = composer
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
    return TimelineViewController(
      coordinator: context.coordinator, timeline: timeline, composer: composer
    )
  }

  func updateNSViewController(_ timelineViewController: TimelineViewController, context: Context) {
    timelineViewController.updateFontSize(fontSize)
  }
}

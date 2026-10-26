import MatrixIntegration
import SwiftUI

struct ChatRoomViewRepresentable: NSViewControllerRepresentable {
  @Environment(AppState.self) private var appState
  @Environment(WindowState.self) private var windowState
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AppStorage("fontSize") private var fontSize = 13

  let timeline: LiveTimeline
  let composer: ChatComposerState

  func makeNSViewController(context: Context) -> ChatRoomViewController {
    ChatRoomViewController(
      appState: appState, windowState: windowState, timeline: timeline, composer: composer)
  }

  func updateNSViewController(_ controller: ChatRoomViewController, context: Context) {
    controller.update(fontSize: fontSize, reduceTransparency: reduceTransparency)
  }

  static func dismantleNSViewController(_ controller: ChatRoomViewController, coordinator: ()) {
    controller.tearDown()
  }
}

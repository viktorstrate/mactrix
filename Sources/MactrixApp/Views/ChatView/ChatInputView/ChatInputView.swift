import AppKit
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct ChatInputView: NSViewControllerRepresentable {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AppStorage("fontSize") private var fontSize = 13
  let room: Room
  let timeline: LiveTimeline
  let composer: ChatComposerState

  func makeNSViewController(context: Context) -> ChatInputViewController {
    ChatInputViewController(room: room, timeline: timeline, composer: composer)
  }

  func updateNSViewController(_ controller: ChatInputViewController, context: Context) {
    controller.update(fontSize: fontSize, reduceTransparency: reduceTransparency)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsViewController: ChatInputViewController,
    context: Context
  ) -> CGSize? {
    let width = proposal.width ?? 400
    return CGSize(width: width, height: nsViewController.container.height(for: width))
  }

  static func dismantleNSViewController(_ controller: ChatInputViewController, coordinator: ()) {
    controller.tearDown()
  }
}

/// Shared routing and highlight state for both native destinations.
@MainActor
final class ComposerAttachmentDropDestination {
  var enabled = false
  var onHighlight: ((Bool) -> Void)?
  var onDrop: ((NSPasteboard) -> Bool)?

  func recognizes(_ sender: any NSDraggingInfo) -> Bool {
    ComposerAttachmentInputAdapter.canImportAttachments(from: sender.draggingPasteboard)
  }

  func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
    ComposerAttachmentInputAdapter.attachmentOperation(
      from: sender.draggingPasteboard, sourceOperations: sender.draggingSourceOperationMask,
      enabled: enabled)
  }

  func entered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let result = operation(sender)
    onHighlight?(result == .copy)
    return result
  }

  func exited() {
    onHighlight?(false)
  }

  func perform(_ sender: any NSDraggingInfo) -> Bool {
    onHighlight?(false)
    guard operation(sender) == .copy else { return false }
    return onDrop?(sender.draggingPasteboard) ?? false
  }
}

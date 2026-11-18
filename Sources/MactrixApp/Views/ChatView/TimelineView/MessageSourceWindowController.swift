import AppKit

@MainActor
final class MessageSourceWindowController: NSWindowController, NSWindowDelegate {
  // Source windows can outlive the timeline that opened them.
  private static var openWindows: [MessageSourceWindowController] = []

  static func show(source: String?) {
    let controller = MessageSourceWindowController(source: source)
    openWindows.append(controller)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private init(source: String?) {
    let sourceWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false)
    sourceWindow.title = String(localized: "Message Source")
    sourceWindow.minSize = NSSize(width: 320, height: 200)
    sourceWindow.isReleasedWhenClosed = false
    sourceWindow.level = .normal
    sourceWindow.tabbingMode = .disallowed

    super.init(window: sourceWindow)
    sourceWindow.delegate = self

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    sourceWindow.contentView = scrollView

    let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textColor = .textColor
    textView.backgroundColor = .textBackgroundColor
    textView.textContainerInset = NSSize(width: 12, height: 12)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = true
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.containerSize = textView.maxSize
    textView.textContainer?.widthTracksTextView = false
    textView.string =
      source.map(Self.prettyPrintedJSON)
      ?? String(
        localized:
          "Message source is not available yet. Local messages must be echoed back by the server before their raw source is available."
      )
    scrollView.documentView = textView
    sourceWindow.initialFirstResponder = textView
    sourceWindow.center()
  }

  private static func prettyPrintedJSON(_ source: String) -> String {
    guard let value = try? JSONSerialization.jsonObject(with: Data(source.utf8)),
      let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
      let formatted = String(data: data, encoding: .utf8)
    else { return source }
    return formatted
  }

  func windowWillClose(_ notification: Notification) {
    Self.openWindows.removeAll { $0 === self }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

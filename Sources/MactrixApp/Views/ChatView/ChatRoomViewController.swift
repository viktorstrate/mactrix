import AppKit
import MatrixIntegration

final class ChatRoomViewController: NSViewController {
  let timelineController: TimelineViewController
  let composerController: ChatInputViewController

  init(
    appState: AppState, windowState: WindowState, timeline: LiveTimeline,
    composer: ChatComposerState
  ) {
    timelineController = TimelineViewController(
      appState: appState, windowState: windowState, timeline: timeline, composer: composer)
    composerController = ChatInputViewController(
      room: timeline.room.room, timeline: timeline, composer: composer)
    super.init(nibName: nil, bundle: nil)
  }

  override func loadView() {
    addChild(timelineController)
    addChild(composerController)
    view = ChatRoomContainerView(
      timelineView: timelineController.view, composer: composerController.composerView)
  }

  func update(fontSize: Int, reduceTransparency: Bool) {
    loadViewIfNeeded()
    timelineController.updateFontSize(fontSize)
    composerController.update(fontSize: fontSize, reduceTransparency: reduceTransparency)
  }

  func tearDown() {
    timelineController.tearDown()
    composerController.tearDown()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The timeline is a flexible viewport; only the composer is measured from content.
final class ChatRoomContainerView: NSView {
  let timelineView: NSView
  let composer: ChatComposerContainer

  init(timelineView: NSView, composer: ChatComposerContainer) {
    self.timelineView = timelineView
    self.composer = composer
    super.init(frame: .zero)
    wantsLayer = true
    for child in [timelineView, composer] {
      child.translatesAutoresizingMaskIntoConstraints = true
      child.autoresizingMask = []
      addSubview(child)
    }

  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    // The scroll view automatically handles the toolbar inset. Only reserve the
    // bottom safe area here, so that it is not also applied to the timeline.
    let bottom = safeAreaInsets.bottom
    let availableHeight = max(0, bounds.height - bottom)

    let composerHeight = min(availableHeight, composer.height(for: bounds.width))
    composer.frame = NSRect(
      x: bounds.minX, y: bounds.minY + bottom,
      width: bounds.width, height: composerHeight)

    let timelineBottom = min(bounds.maxY, composer.frame.maxY)
    timelineView.frame = NSRect(
      x: bounds.minX, y: timelineBottom, width: bounds.width,
      height: max(0, bounds.maxY - timelineBottom))

    super.layout()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

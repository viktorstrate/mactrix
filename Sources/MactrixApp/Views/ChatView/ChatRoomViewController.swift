import AppKit
import MatrixIntegration
import OSLog

final class ChatRoomViewController: NSViewController {
  let timelineController: TimelineViewController
  let composerController: ChatInputViewController
  private var composerAccessory: NSViewController?

  init(
    appState: AppState, windowState: WindowState, timeline: LiveTimeline,
    composer: ChatComposerState
  ) {
    timelineController = TimelineViewController(
      appState: appState, windowState: windowState, timeline: timeline, composer: composer)
    composerController = ChatInputViewController(
      room: timeline.room.room, timeline: timeline, composer: composer,
      imageLoader: appState.matrixClient)
    super.init(nibName: nil, bundle: nil)
  }

  override func loadView() {
    addChild(timelineController)
    addChild(composerController)
    view = ChatRoomContainerView(
      timelineView: timelineController.view, composer: composerController.composerView)
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    guard #available(macOS 26.0, *), composerAccessory == nil else { return }
    if let splitView = enclosingSplitViewItem {
      let accessory = ChatComposerAccessoryViewController(composerController: composerController)
      composerAccessory = accessory
      composerController.view.removeFromSuperview()
      composerController.removeFromParent()
      view.needsLayout = true
      splitView.addBottomAlignedAccessoryViewController(accessory)

      Logger.composerView.debug(
        "Attached composer accessory to \(type(of: splitView.viewController))")
    } else {
      Logger.composerView.debug("No enclosing split-view item; keeping composer overlay")
      return
    }
  }

  private var enclosingSplitViewItem: NSSplitViewItem? {
    var ancestor = view.superview
    while let current = ancestor {
      if let splitView = current as? NSSplitView,
        let controller = splitView.delegate as? NSSplitViewController,
        let item = controller.splitViewItems.first(where: {
          $0.viewController.isViewLoaded && view.isDescendant(of: $0.viewController.view)
        })
      {
        return item
      }
      ancestor = current.superview
    }
    return nil
  }

  func update(fontSize: Int, reduceTransparency: Bool) {
    loadViewIfNeeded()
    timelineController.updateFontSize(fontSize)
    composerController.update(fontSize: fontSize, reduceTransparency: reduceTransparency)
  }

  func tearDown() {
    timelineController.tearDown()
    composerController.tearDown()
    composerAccessory?.removeFromParent()
    composerAccessory = nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@available(macOS 26.0, *)
private final class ChatComposerAccessoryViewController: NSSplitViewItemAccessoryViewController {
  private let composerController: ChatInputViewController
  private var restoreClipping: (() -> Void)?

  init(composerController: ChatInputViewController) {
    self.composerController = composerController
    super.init(nibName: nil, bundle: nil)
    automaticallyAppliesContentInsets = false
    if #available(macOS 26.1, *) {
      preferredScrollEdgeEffectStyle = .soft
    }
  }

  override func loadView() {
    addChild(composerController)
    view = ChatComposerAccessoryContainerView(composer: composerController.composerView)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    disableShadowClipping()
  }

  /// Access the internal view that clips the shadow of the composer view.
  /// This internal view is not directly accessible on the super views.
  /// The method attempts to find it to disable clipping.
  private func disableShadowClipping() {
    guard restoreClipping == nil else { return }
    var ancestor = view.superview
    while let current = ancestor, !(current is NSSplitView) {
      if current.clipsToBounds || current.layer?.masksToBounds == true {
        let layer = current.layer
        let clipping = (current.clipsToBounds, layer?.masksToBounds ?? false)
        restoreClipping = { [weak current, weak layer] in
          current?.clipsToBounds = clipping.0
          layer?.masksToBounds = clipping.1
        }
        current.clipsToBounds = false
        layer?.masksToBounds = false
        current.superview?.needsDisplay = true
        return
      }
      ancestor = current.superview
    }
    Logger.composerView.info("No matching accessory clip found; clipping unchanged")
  }

  override func viewWillDisappear() {
    restoreClipping?()
    restoreClipping = nil
    super.viewWillDisappear()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class ChatComposerAccessoryContainerView: NSView {
  private let composer: ChatComposerContainer
  private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

  init(composer: ChatComposerContainer) {
    self.composer = composer
    super.init(frame: NSRect(origin: .zero, size: composer.frame.size))
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(composer)
    heightConstraint.constant = composer.height(for: bounds.width)
    heightConstraint.priority = .defaultHigh
    heightConstraint.isActive = true
  }

  override func layout() {
    let height = composer.height(for: bounds.width)
    if heightConstraint.constant != height {
      heightConstraint.constant = height
    }
    composer.frame = bounds
    super.layout()
  }

  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = frame.width != newSize.width
    super.setFrameSize(newSize)
    if widthChanged { needsLayout = true }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

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
    timelineView.frame = bounds
    if composer.superview === self {
      let bottom = safeAreaInsets.bottom
      let availableHeight = max(0, bounds.height - bottom)
      let composerHeight = min(availableHeight, composer.height(for: bounds.width))
      composer.frame = NSRect(
        x: bounds.minX, y: bounds.minY + bottom,
        width: bounds.width, height: composerHeight)
      timelineView.additionalSafeAreaInsets.bottom = composerHeight
    } else {
      // The split-view accessory now provides the composer's safe-area reservation.
      timelineView.additionalSafeAreaInsets.bottom = 0
    }

    super.layout()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

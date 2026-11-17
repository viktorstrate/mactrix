import AppKit
import SwiftUI

/// Owns one main window's popup, independently of menu commands and room navigation.
@MainActor @Observable
final class QuickNavigationCoordinator: NSObject {
  private(set) weak var parentWindow: NSWindow?
  private(set) var popup: QuickNavigationWindow?
  private weak var previousResponder: NSResponder?
  var isSignedIn = false {
    didSet {
      guard isSignedIn != oldValue else { return }
      if !isSignedIn { dismiss(restoreFocus: false) }

    }
  }

  func attach(to window: NSWindow?) {
    guard parentWindow !== window else { return }
    dismiss(restoreFocus: false)
    parentWindow = window
  }

  func present(
    candidates: [QuickNavigationCandidate] = [],
    onSubmit: @escaping (QuickNavigationCandidate) -> Void = { _ in }
  ) {
    guard popup == nil, let parent = parentWindow, parent.isVisible else { return }
    // A field editor is shared by its window; restore its control, not the editor itself.
    if let editor = parent.firstResponder as? NSTextView, editor.isFieldEditor {
      previousResponder = editor.delegate as? NSResponder
    } else {
      previousResponder = parent.firstResponder
    }

    let session = QuickNavigationSession()
    session.updateCandidates(candidates)
    let popup = QuickNavigationWindow(session: session)
    self.popup = popup
    popup.onSubmit = onSubmit
    popup.onDismiss = { [weak self] in self?.dismiss() }
    popup.onSearchFocusLost = { [weak self] in self?.dismiss(restoreFocus: false) }
    popup.onPreferredSizeChange = { [weak self] in self?.reposition() }
    observe(parent: parent, popup: popup)
    reposition()
    parent.addChildWindow(popup, ordered: .above)
    popup.makeKeyAndOrderFront(nil)
  }

  func dismiss(restoreFocus: Bool = true) {
    guard let popup else { return }
    let parent = parentWindow
    let shouldRestore =
      restoreFocus && NSApp.isActive && parent?.isVisible == true
      && (NSApp.keyWindow === popup || NSApp.keyWindow === parent)
    let responder = previousResponder
    self.popup = nil
    previousResponder = nil
    NotificationCenter.default.removeObserver(self)
    popup.onDismiss = nil
    popup.onSubmit = nil
    popup.onSearchFocusLost = nil
    popup.onPreferredSizeChange = nil
    popup.parent?.removeChildWindow(popup)
    popup.orderOut(nil)
    popup.close()

    if shouldRestore, let parent {
      // Do not reintroduce a responder whose view was removed while the popup was open.
      parent.makeKey()
      if let view = responder as? NSView, view.window !== parent { return }
      if let responder { parent.makeFirstResponder(responder) }
    }
  }

  @objc private func reposition() {
    guard let parent = parentWindow, let popup else { return }
    let frame = Self.frame(
      parentFrame: parent.frame,
      visibleFrame: parent.screen?.visibleFrame ?? parent.frame,
      preferredSize: popup.navigationView.preferredSize)
    if popup.frame != frame { popup.setFrame(frame, display: true) }
  }

  /// The top is independent of result count, even when the results must scroll to fit.
  static func frame(parentFrame: NSRect, visibleFrame: NSRect, preferredSize: NSSize) -> NSRect {
    let intersection = parentFrame.intersection(visibleFrame)
    let bounds = intersection.isNull || intersection.isEmpty ? visibleFrame : intersection
    let inset = min(12, min(bounds.width, bounds.height) / 4)
    let available = bounds.insetBy(dx: inset, dy: inset)
    let top = min(
      available.maxY,
      max(parentFrame.maxY - 100, available.minY + min(133, available.height)))
    let size = NSSize(
      width: min(preferredSize.width, available.width),
      height: min(preferredSize.height, top - available.minY))
    let x = min(
      max(parentFrame.midX - size.width / 2, available.minX), available.maxX - size.width)
    return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
  }

  private func observe(parent: NSWindow, popup: NSWindow) {
    let center = NotificationCenter.default
    for name in [
      NSWindow.didMoveNotification, NSWindow.didResizeNotification,
      NSWindow.didChangeScreenNotification, NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
    ] {
      center.addObserver(self, selector: #selector(reposition), name: name, object: parent)
    }
    center.addObserver(
      self, selector: #selector(lostFocus), name: NSWindow.didResignKeyNotification, object: popup)
    center.addObserver(
      self, selector: #selector(lostFocus), name: NSWindow.willCloseNotification, object: popup)
    center.addObserver(
      self, selector: #selector(parentWillClose), name: NSWindow.willCloseNotification,
      object: parent)
    center.addObserver(
      self, selector: #selector(lostFocus), name: NSApplication.didResignActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(reposition),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil)
  }

  @objc private func lostFocus() {
    dismiss(restoreFocus: false)
  }

  @objc private func parentWillClose() {
    attach(to: nil)
  }
}

/// Resolves the actual hosting window rather than relying on window ordering or scene focus.
struct QuickNavigationWindowAttachment: NSViewRepresentable {
  let coordinator: QuickNavigationCoordinator
  var isSignedIn = false

  func makeNSView(context: Context) -> AttachmentView {
    AttachmentView(coordinator: coordinator)
  }

  func updateNSView(_ nsView: AttachmentView, context: Context) {
    if nsView.coordinator !== coordinator {
      nsView.coordinator.attach(to: nil)
      nsView.coordinator = coordinator
    }
    coordinator.isSignedIn = isSignedIn
    coordinator.attach(to: nsView.window)
  }

  static func dismantleNSView(_ nsView: AttachmentView, coordinator: Void) {
    nsView.coordinator.attach(to: nil)
  }

  final class AttachmentView: NSView {
    var coordinator: QuickNavigationCoordinator

    init(coordinator: QuickNavigationCoordinator) {
      self.coordinator = coordinator
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      coordinator.attach(to: window)
    }
  }
}

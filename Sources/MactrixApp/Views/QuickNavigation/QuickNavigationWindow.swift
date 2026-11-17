import AppKit
import MactrixUI

/// Standalone presentation. The owner handles attachment, navigation, and dismissal.
@MainActor
final class QuickNavigationWindow: NSWindow {
  let navigationView: QuickNavigationView
  var onSubmit: ((QuickNavigationCandidate) -> Void)?
  var onDismiss: (() -> Void)?
  var onPreferredSizeChange: (() -> Void)?

  init(session: QuickNavigationSession = QuickNavigationSession()) {
    navigationView = QuickNavigationView(session: session)
    super.init(
      contentRect: NSRect(origin: .zero, size: navigationView.preferredSize),
      styleMask: [.borderless], backing: .buffered, defer: true)
    title = "Quick Navigation"
    isReleasedWhenClosed = false
    hasShadow = true
    isOpaque = false
    backgroundColor = .clear
    collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
    isMovable = false
    hidesOnDeactivate = true
    contentView = navigationView
    initialFirstResponder = navigationView.searchField

    navigationView.onSubmit = { [weak self] candidate in self?.onSubmit?(candidate) }
    navigationView.onDismiss = { [weak self] in self?.onDismiss?() }
    navigationView.onPreferredSizeChange = { [weak self] in
      guard let self else { return }
      if let onPreferredSizeChange {
        onPreferredSizeChange()
      } else {
        // Keep the top edge anchored while a standalone popup changes result count.
        let size = navigationView.preferredSize
        setFrame(
          NSRect(
            x: frame.minX, y: frame.maxY - size.height, width: frame.width, height: size.height),
          display: true)
      }
    }
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    super.makeKeyAndOrderFront(sender)
    makeFirstResponder(navigationView.searchField)
  }
}

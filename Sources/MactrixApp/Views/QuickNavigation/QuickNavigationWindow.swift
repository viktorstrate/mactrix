import AppKit
import MactrixUI

/// Child panel presentation. The owner handles attachment, navigation, and dismissal.
@MainActor
final class QuickNavigationWindow: NSPanel {
  let navigationView: QuickNavigationView
  var onSubmit: ((QuickNavigationCandidate) -> Void)?
  var onDismiss: (() -> Void)?
  var onSearchFocusLost: (() -> Void)?
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
    let container = NSView(frame: NSRect(origin: .zero, size: navigationView.preferredSize))
    navigationView.frame = container.bounds
    navigationView.autoresizingMask = [.width, .height]
    container.addSubview(navigationView)
    contentView = container
    initialFirstResponder = navigationView.searchField

    navigationView.onSubmit = { [weak self] candidate in self?.onSubmit?(candidate) }
    navigationView.onDismiss = { [weak self] in self?.onDismiss?() }
    navigationView.onSearchFocusLost = { [weak self] in self?.onSearchFocusLost?() }
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

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown,
      event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
      event.charactersIgnoringModifiers?.lowercased() == "k"
    {
      onDismiss?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    super.makeKeyAndOrderFront(sender)
    if navigationView.searchField.currentEditor() !== firstResponder
      || navigationView.searchField.currentEditor() == nil
    {
      makeFirstResponder(navigationView.searchField)
    }
  }
}

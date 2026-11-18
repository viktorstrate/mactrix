import AppKit
import SwiftUI

/// Resolves the scene's window, then installs above its entire content tree, including inspectors.
struct QuickNavigationOverlayAttachment: NSViewRepresentable {
  let coordinator: QuickNavigationCoordinator
  var isSignedIn = false

  func makeNSView(context: Context) -> AttachmentView {
    AttachmentView(coordinator: coordinator)
  }

  func updateNSView(_ nsView: AttachmentView, context: Context) {
    if nsView.coordinator !== coordinator {
      nsView.uninstall()
      nsView.coordinator = coordinator
    }
    coordinator.isSignedIn = isSignedIn
    nsView.installIfNeeded()
  }

  static func dismantleNSView(_ nsView: AttachmentView, coordinator: Void) {
    nsView.uninstall()
  }

  final class AttachmentView: NSView {
    var coordinator: QuickNavigationCoordinator
    private var host: QuickNavigationOverlayHost?

    init(coordinator: QuickNavigationCoordinator) {
      self.coordinator = coordinator
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installIfNeeded()
    }

    func installIfNeeded() {
      guard host?.window !== window || host == nil else { return }
      uninstall()
      guard let window, let contentView = window.contentView,
        let contentContainer = contentView.superview
      else { return }
      let host = QuickNavigationOverlayHost(frame: contentView.frame)
      host.translatesAutoresizingMaskIntoConstraints = false
      self.host = host
      // SwiftUI can reorder the content view's children when presenting its inspector.
      // Keep the overlay a sibling of the hosting root, outside that managed subtree.
      contentContainer.addSubview(host, positioned: .above, relativeTo: contentView)
      NSLayoutConstraint.activate([
        host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        host.topAnchor.constraint(equalTo: contentView.topAnchor),
        host.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
      coordinator.attach(to: host)
    }

    func uninstall() {
      guard let host else { return }
      if coordinator.host === host { coordinator.attach(to: nil) }
      host.removeFromSuperview()
      self.host = nil
    }
  }
}

@MainActor
final class QuickNavigationOverlayHost: NSView {
  private(set) var surface: QuickNavigationShadowView?
  var onWindowChange: (() -> Void)?

  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?()
  }

  func present(_ navigationView: QuickNavigationView) {
    removeNavigation()
    let surface = QuickNavigationShadowView(navigationView: navigationView)
    self.surface = surface
    addSubview(surface)
    layoutNavigation()
  }

  func removeNavigation() {
    surface?.removeFromSuperview()
    surface = nil
  }

  override func layout() {
    super.layout()
    layoutNavigation()
  }

  func layoutNavigation() {
    guard let surface else { return }
    let contentBounds =
      window.map { convert($0.contentLayoutRect, from: nil).intersection(bounds) }
      ?? bounds
    surface.frame = Self.frame(
      contentBounds: contentBounds, preferredSize: surface.navigationView.preferredSize)
    surface.layoutSubtreeIfNeeded()
  }

  /// Flipped content coordinates keep the top independent of result count and available height.
  static func frame(contentBounds: NSRect, preferredSize: NSSize) -> NSRect {
    let width = max(0, contentBounds.width)
    let height = max(0, contentBounds.height)
    let sideInset = min(16, width / 4)
    let topInset = min(32, height / 4)
    let bottomInset = min(16, height / 4)
    let size = NSSize(
      width: max(0, min(preferredSize.width, width - 2 * sideInset)),
      height: max(0, min(preferredSize.height, height - topInset - bottomInset)))
    return NSRect(
      x: contentBounds.midX - size.width / 2, y: contentBounds.minY + topInset,
      width: size.width, height: size.height)
  }

  func containsNavigationPoint(_ pointInWindow: NSPoint) -> Bool {
    guard let surface else { return false }
    return surface.bounds.contains(surface.convert(pointInWindow, from: nil))
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let surface, surface.frame.contains(convert(point, from: superview)) else { return nil }
    return super.hitTest(point)
  }
}

/// The material clips its corners; this separate, transparent layer lets its shadow extend outside.
@MainActor
final class QuickNavigationShadowView: NSView {
  let navigationView: QuickNavigationView

  init(navigationView: QuickNavigationView) {
    self.navigationView = navigationView
    super.init(frame: NSRect(origin: .zero, size: navigationView.preferredSize))
    wantsLayer = true
    layer?.masksToBounds = false
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    self.shadow = shadow
    navigationView.frame = bounds
    navigationView.autoresizingMask = [.width, .height]
    addSubview(navigationView)
  }

  required init?(coder: NSCoder) { nil }
}

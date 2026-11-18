import AppKit
import MatrixIntegration
import SwiftUI

/// Owns one main window's navigation session without creating or activating another window.
@MainActor @Observable
final class QuickNavigationCoordinator: NSObject {
  private(set) weak var host: QuickNavigationOverlayHost?
  var parentWindow: NSWindow? { host?.window }
  private var navigationView: QuickNavigationView? { host?.surface?.navigationView }
  private weak var previousResponder: NSResponder?
  private var eventMonitor: Any?
  @ObservationIgnored private weak var matrixClient: MatrixClient?
  @ObservationIgnored private var onSelectRoom: ((String) -> Void)?

  var isSignedIn = false {
    didSet {
      if !isSignedIn { dismiss() }
    }
  }

  func configure(matrixClient: MatrixClient?, onSelectRoom: @escaping (String) -> Void) {
    if self.matrixClient !== matrixClient { dismiss() }
    self.matrixClient = matrixClient
    self.onSelectRoom = onSelectRoom
    isSignedIn = matrixClient != nil
  }

  func attach(to host: QuickNavigationOverlayHost?) {
    guard self.host !== host else { return }
    dismiss()
    self.host = host
  }

  func toggle() {
    if navigationView == nil {
      guard let matrixClient else { return }
      present(candidates: candidates(from: matrixClient)) {
        [weak self, weak matrixClient] candidate in
        // Observation delivery is deferred; validate against the current list at submission too.
        guard let self, let matrixClient, self.matrixClient === matrixClient,
          matrixClient.rooms.contains(where: { $0.id == candidate.id })
        else { return }
        onSelectRoom?(candidate.id)
      }
      if let navigationView {
        navigationView.imageLoader = matrixClient
        observeRooms(matrixClient, for: navigationView)
      }
    } else {
      cancel()
    }
  }

  func present(
    candidates: [QuickNavigationCandidate] = [],
    onSubmit: @escaping (QuickNavigationCandidate) -> Void = { _ in }
  ) {
    guard navigationView == nil, isSignedIn, let host, let parent = host.window,
      parent.isVisible, parent.isKeyWindow, NSApp.isActive,
      parent.attachedSheet == nil, !parent.isMiniaturized
    else { return }
    // A field editor is shared by its window; restore its control, not the editor itself.
    if let editor = parent.firstResponder as? NSTextView, editor.isFieldEditor {
      previousResponder = editor.delegate as? NSResponder
    } else {
      previousResponder = parent.firstResponder
    }

    let session = QuickNavigationSession()
    session.updateCandidates(candidates)
    let navigationView = QuickNavigationView(session: session)

    navigationView.onSubmit = { [weak self] candidate in
      guard let self, self.navigationView != nil else { return }
      dismiss()
      onSubmit(candidate)
    }
    navigationView.onDismiss = { [weak self] in self?.cancel() }
    navigationView.onSearchFocusLost = { [weak self, weak navigationView] in
      self?.scheduleFocusCheck(for: navigationView)
    }
    navigationView.onPreferredSizeChange = { [weak host] in host?.layoutNavigation() }
    host.present(navigationView)
    observe(parent: parent)
    // Never change key/main window identity just to edit the search field.
    if !parent.makeFirstResponder(navigationView.searchField) {
      cancel()
    }
  }

  private func candidates(from matrixClient: MatrixClient) -> [QuickNavigationCandidate] {
    matrixClient.rooms.map { entry in
      // Read observable roomInfo, not just SDK getters, so metadata updates invalidate the list.
      let info = entry.roomInfo
      return QuickNavigationCandidate(
        id: entry.id,
        displayName: info == nil ? entry.room.displayName() : info?.displayName,
        canonicalAlias: info == nil ? entry.room.canonicalAlias() : info?.canonicalAlias,
        avatarUrl: info == nil ? entry.room.avatarUrl() : info?.avatarUrl)
    }
  }

  private func observeRooms(_ matrixClient: MatrixClient, for view: QuickNavigationView) {
    guard navigationView === view, self.matrixClient === matrixClient else { return }

    let updated = withObservationTracking {
      candidates(from: matrixClient)
    } onChange: { [weak self, weak matrixClient, weak view] in
      Task { @MainActor [weak self, weak matrixClient, weak view] in
        guard let self, let matrixClient, let view else { return }
        // A callback from a dismissed presentation must not update a later session.
        observeRooms(matrixClient, for: view)
      }
    }
    view.session.updateCandidates(updated)
  }

  func cancel() {
    removePresentation(restoreFocus: true)
  }

  @objc func dismiss() {
    removePresentation(restoreFocus: false)
  }

  private func removePresentation(restoreFocus: Bool) {
    guard let navigationView else { return }
    let parent = parentWindow
    let responder = previousResponder
    previousResponder = nil
    NotificationCenter.default.removeObserver(self)
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
    navigationView.onDismiss = nil
    navigationView.onSubmit = nil
    navigationView.onSearchFocusLost = nil
    navigationView.onPreferredSizeChange = nil

    // Do not leave the shared field editor targeting a control in a removed overlay.
    if contains(parent?.firstResponder, in: navigationView) {
      parent?.makeFirstResponder(nil)
    }
    host?.removeNavigation()

    guard restoreFocus, NSApp.isActive, let parent,
      parent.isVisible, parent.isKeyWindow, let responder,
      responderBelongsToWindow(responder, window: parent)
    else { return }
    parent.makeFirstResponder(responder)
  }

  private func responderBelongsToWindow(_ responder: NSResponder, window: NSWindow) -> Bool {
    if let view = responder as? NSView { return view.window === window }
    if let controller = responder as? NSWindowController { return controller.window === window }
    return responder === window
  }

  private func contains(_ responder: NSResponder?, in navigationView: QuickNavigationView) -> Bool {
    if let editor = responder as? NSTextView, editor.isFieldEditor {
      guard let control = editor.delegate as? NSView else { return false }
      return control === navigationView || control.isDescendant(of: navigationView)
    }
    guard let view = responder as? NSView else { return false }
    return view === navigationView || view.isDescendant(of: navigationView)
  }

  private func scheduleFocusCheck(for view: QuickNavigationView?) {
    // End-editing runs before AppKit finishes installing the new responder. Check afterwards,
    // and identify the session so a stale callback cannot dismiss a subsequent presentation.
    DispatchQueue.main.async { [weak self, weak view] in
      guard let self, let view, navigationView === view else { return }
      guard (view.searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
        return
      }
      if !contains(parentWindow?.firstResponder, in: view) { dismiss() }
    }
  }

  private func observe(parent: NSWindow) {
    let center = NotificationCenter.default
    for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
      center.addObserver(self, selector: #selector(dismiss), name: name, object: parent)
    }
    center.addObserver(
      self, selector: #selector(dismiss), name: NSApplication.didResignActiveNotification,
      object: nil)
    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self, event.window === parentWindow else { return event }
      if host?.containsNavigationPoint(event.locationInWindow) == false {
        dismiss()
      }
      // AppKit delivers the original click to its target; no redispatch or focus restoration.
      return event
    }
  }
}

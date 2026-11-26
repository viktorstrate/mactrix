import AppKit
import SwiftUI

/// Reports the window that hosts it, the window it moves to later, and when that window closes.
struct WindowReader: NSViewRepresentable {
  let onChange: (NSWindow?) -> Void
  let onClose: () -> Void

  func makeNSView(context: Context) -> ReportingView {
    ReportingView(onChange: onChange, onClose: onClose)
  }

  func updateNSView(_ view: ReportingView, context: Context) {
    view.onChange = onChange
    view.onClose = onClose
    // The receiver may be new, so report the current window to it too.
    if let window = view.window {
      onChange(window)
    }
  }

  final class ReportingView: NSView {
    var onChange: (NSWindow?) -> Void
    var onClose: () -> Void
    private var closeObserver: NSObjectProtocol?

    init(onChange: @escaping (NSWindow?) -> Void, onClose: @escaping () -> Void) {
      self.onChange = onChange
      self.onClose = onClose
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let closeObserver {
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
      }
      if let window {
        closeObserver = NotificationCenter.default.addObserver(
          forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.onClose() }
        }
      }
      onChange(window)
    }
  }
}

import AppKit

/// Prototype toolbar surface that can extend across timeline rows.
final class MessageHoverOverlayView: NSView {
    var onMouseExited: ((NSEvent) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 28))

        wantsLayer = true
        layer?.backgroundColor = NSColor.systemPink.cgColor
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?(event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

import AppKit
import SwiftUI
import UI

/// A floating panel that displays message hover actions (react, reply, pin)
/// positioned above the hovered timeline row, outside the NSTableView's row clipping.
class HoverActionsPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>

    init() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }

    var isMouseInside: Bool {
        NSMouseInRect(NSEvent.mouseLocation, frame, false)
    }

    func update(eventId: String, onReaction: @escaping (String) -> Void, onReply: @escaping () -> Void, onReplyInThread: @escaping () -> Void, onPin: @escaping () -> Void) {
        hostingView.rootView = AnyView(
            HoverActionsView(onReaction: onReaction, onReply: onReply, onReplyInThread: onReplyInThread, onPin: onPin)
                .id(eventId)
        )
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        setContentSize(size)
    }

    func position(relativeTo rowRect: NSRect, in window: NSWindow, topOffset: CGFloat = 0) {
        let screenRect = window.convertToScreen(rowRect)
        let size = hostingView.fittingSize
        let origin = NSPoint(
            x: screenRect.maxX - size.width - 20,
            y: screenRect.maxY - 6 - topOffset
        )
        setFrameOrigin(origin)
    }
}

private struct HoverActionsView: View {
    let onReaction: (String) -> Void
    let onReply: () -> Void
    let onReplyInThread: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HoverButton(icon: { Text("👍") }, tooltip: "React") { onReaction("👍") }
            HoverButton(icon: { Text("🎉") }, tooltip: "React") { onReaction("🎉") }
            HoverButton(icon: { Text("❤️") }, tooltip: "React") { onReaction("❤️") }
            Divider().frame(height: 18)
            HoverButton(icon: { Image(systemName: "face.smiling") }, tooltip: "React") {}
            HoverButton(icon: { Image(systemName: "arrowshape.turn.up.left") }, tooltip: "Reply") { onReply() }
            HoverButton(icon: { Image(systemName: "ellipsis.message") }, tooltip: "Reply in thread") { onReplyInThread() }

            HoverButton(icon: { Image(systemName: "pin") }, tooltip: "Pin") { onPin() }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
}

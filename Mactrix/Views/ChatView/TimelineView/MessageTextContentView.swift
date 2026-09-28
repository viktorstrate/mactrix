import AppKit
import MatrixRustSDK
import MessageFormatting

/// Retains the NSTextView and its layout machinery when its table row is reused.
final class MessageTextContentView: NSView {
    var onTextMouseDown: (() -> Void)?
    var onArrowKey: ((TimelineSelectionDirection) -> Void)?
    private let bodyText = OcclusionAwareTextView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        bodyText.isSelectable = true
        bodyText.isEditable = false
        bodyText.isRichText = true
        bodyText.drawsBackground = false
        bodyText.textContainerInset = .zero
        bodyText.textContainer?.lineFragmentPadding = 0
        bodyText.textContainer?.widthTracksTextView = true
        bodyText.isHorizontallyResizable = false
        bodyText.isVerticallyResizable = true
        bodyText.translatesAutoresizingMaskIntoConstraints = false
        bodyText.onMouseDown = { [weak self] in self?.onTextMouseDown?() }
        bodyText.onArrowKey = { [weak self] direction in self?.onArrowKey?(direction) }

        addSubview(bodyText)
        NSLayoutConstraint.activate([
            bodyText.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyText.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyText.topAnchor.constraint(equalTo: topAnchor),
            bodyText.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    static func supports(content: MsgLikeContent) -> Bool {
        guard case let .message(message) = content.kind else { return false }
        switch message.msgType {
        case .text, .notice: return true
        default: return false
        }
    }

    func configure(content: MsgLikeContent) {
        bodyText.textStorage?.setAttributedString(Self.attributedBody(for: content))
    }

    func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
        guard let textStorage = bodyText.textStorage,
              let layoutManager = bodyText.layoutManager,
              let textContainer = bodyText.textContainer else { return 20 }

        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textStorage.setAttributedString(Self.attributedBody(for: content))
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).height
    }

    private static func attributedBody(for content: MsgLikeContent) -> NSAttributedString {
        let fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
        guard case let .message(message) = content.kind else { return NSAttributedString() }

        switch message.msgType {
        case let .text(text):
            return attributedText(for: text, font: font, color: .labelColor)
        case let .notice(notice):
            return attributedText(for: notice, font: font, color: .secondaryLabelColor)
        default:
            return NSAttributedString()
        }
    }

    private static func attributedText(
        for message: some MessageContent, font: NSFont, color: NSColor
    ) -> NSAttributedString {
        if let formatted = message.formatted, formatted.format == .html {
            let result = NSMutableAttributedString(attributedString: parseFormattedBody(
                formatted.body, baseFontSize: font.pointSize
            ))
            if color == .secondaryLabelColor {
                result.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
            }
            return result
        }
        return NSAttributedString(string: message.body.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Lets a view drawn above the text own the cursor without knowing what that view is.
private final class OcclusionAwareTextView: NSTextView {
    var onMouseDown: (() -> Void)?
    var onArrowKey: ((TimelineSelectionDirection) -> Void)?

    override func keyDown(with event: NSEvent) {
        if let direction = TimelineSelectionDirection(event: event), let onArrowKey {
            onArrowKey(direction)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard shouldHandlePointerEvent(event) else { return }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // NSTextView also sets its cursor during mouse movement, independently
        // of cursorUpdate. Covered text must yield to the view above it here too.
        guard shouldHandlePointerEvent(event) else { return }
        super.mouseMoved(with: event)
    }

    private func shouldHandlePointerEvent(_ event: NSEvent) -> Bool {
        guard let window,
              let contentView = window.contentView,
              let contentSuperview = contentView.superview,
              let hitView = contentView.hitTest(contentSuperview.convert(event.locationInWindow, from: nil))
        else {
            return true
        }

        return hitView === self || hitView.isDescendant(of: self)
    }
}

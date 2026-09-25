import AppKit
import MatrixRustSDK
import MessageFormatting

/// The AppKit row for a text message without replies or bottom content.
final class MessageBodyRowView: NSView {
    var onHoverChange: ((MessageBodyRowView, Bool, NSEvent) -> Bool)?

    private let timestamp = NSTextField(labelWithString: "")
    private let bodyText = NSTextView(frame: .zero)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        timestamp.font = .systemFont(ofSize: NSFont.labelFontSize)
        timestamp.textColor = .secondaryLabelColor
        timestamp.alignment = .right
        timestamp.translatesAutoresizingMaskIntoConstraints = false

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

        wantsLayer = true
        layer?.cornerRadius = 4
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        addSubview(timestamp)
        addSubview(bodyText)
        NSLayoutConstraint.activate([
            timestamp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            timestamp.widthAnchor.constraint(equalToConstant: 32 + 16),
            bodyText.leadingAnchor.constraint(equalTo: timestamp.trailingAnchor, constant: 16),
            bodyText.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            bodyText.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            bodyText.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    static func supports(event: EventTimelineItem, content: MsgLikeContent) -> Bool {
        guard content.reactions.isEmpty,
              content.inReplyTo == nil,
              content.threadSummary == nil,
              event.readReceipts.isEmpty,
              case let .message(message) = content.kind else { return false }
        switch message.msgType {
        case .text, .notice: return true
        default: return false
        }
    }

    func configure(event: EventTimelineItem, content: MsgLikeContent) {
        let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
        timestamp.stringValue = Self.timeFormatter.string(from: date)
        bodyText.textStorage?.setAttributedString(Self.attributedBody(for: content))
        layer?.backgroundColor = nil
    }

    override func mouseEntered(with event: NSEvent) {
        if onHoverChange?(self, true, event) ?? true {
            setHoverHighlight(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        setHoverHighlight(onHoverChange?(self, false, event) ?? false)
    }

    func setHoverHighlight(_ highlighted: Bool) {
        layer?.backgroundColor = highlighted ? .init(gray: 0.5, alpha: 0.1) : nil
    }

    func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
        let bodyWidth = max(width - 74, 1)
        guard let textStorage = bodyText.textStorage,
              let layoutManager = bodyText.layoutManager,
              let textContainer = bodyText.textContainer else { return 28 }

        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: bodyWidth, height: .greatestFiniteMagnitude)
        textStorage.setAttributedString(Self.attributedBody(for: content))
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height
        return max(ceil(textHeight) + 8, 28)
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

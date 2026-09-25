import AppKit
import MatrixRustSDK

/// Shared row chrome. The content view is created once and retained across table reuse.
final class MessageRowView: NSView {
    var onHoverChange: ((MessageRowView, Bool, NSEvent) -> Bool)?

    private let timestamp = NSTextField(labelWithString: "")
    private let contentView = MessageTextContentView()

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
        contentView.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 4
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        addSubview(timestamp)
        addSubview(contentView)
        NSLayoutConstraint.activate([
            timestamp.leadingAnchor.constraint(equalTo: leadingAnchor),
            timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            timestamp.widthAnchor.constraint(equalToConstant: 48),

            contentView.leadingAnchor.constraint(equalTo: timestamp.trailingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    static func supports(event: EventTimelineItem, content: MsgLikeContent) -> Bool {
        content.reactions.isEmpty &&
        content.inReplyTo == nil &&
        content.threadSummary == nil &&
        event.readReceipts.isEmpty &&
        MessageTextContentView.supports(content: content)
    }

    func configure(event: EventTimelineItem, content: MsgLikeContent) {
        let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
        timestamp.stringValue = Self.timeFormatter.string(from: date)
        contentView.configure(content: content)
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
        let contentWidth = max(width - 74, 1)
        return max(ceil(contentView.height(for: content, width: contentWidth)) + 8, 28)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

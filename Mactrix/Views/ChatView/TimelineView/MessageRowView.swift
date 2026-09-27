import AppKit
import MatrixRustSDK

/// Shared row chrome. The content view is created once and retained across table reuse.
final class MessageRowView: NSView {
    var onHoverChange: ((MessageRowView, Bool, NSEvent) -> Bool)?

    private static let contentHorizontalInset: CGFloat = 74
    private static let replySpacing: CGFloat = 20
    private static let threadSpacing: CGFloat = 10

    private let timestamp = NSTextField(labelWithString: "")
    private let contentView = MessageTextContentView()
    private var replyPreview: MessageReplyPreviewView?
    private var replyDetails: EmbeddedEventDetails?
    private var replyHeightConstraint: NSLayoutConstraint?
    private var contentTopToReply: NSLayoutConstraint?
    private lazy var contentTopToRow = contentView.topAnchor.constraint(equalTo: topAnchor, constant: 4)
    private var threadSummaryView: MessageThreadSummaryView?
    private var threadHeightConstraint: NSLayoutConstraint?
    private var threadTopConstraint: NSLayoutConstraint?
    private var threadBottomConstraint: NSLayoutConstraint?
    private lazy var contentBottomToRow = contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)

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
            contentTopToRow,
            contentBottomToRow,
        ])
    }

    static func supports(event: EventTimelineItem, content: MsgLikeContent) -> Bool {
        content.reactions.isEmpty &&
        event.readReceipts.isEmpty &&
        MessageTextContentView.supports(content: content)
    }

    func configure(
        event: EventTimelineItem,
        content: MsgLikeContent,
        replyDetails: EmbeddedEventDetails?,
        onReplyClick: (() -> Void)?,
        onThreadClick: (() -> Void)?
    ) {
        let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
        timestamp.stringValue = Self.timeFormatter.string(from: date)
        contentView.configure(content: content)
        configureReply(details: replyDetails, onClick: onReplyClick)
        configureThread(summary: content.threadSummary, onClick: onThreadClick)
        layer?.backgroundColor = nil
    }

    private func configureThread(summary: ThreadSummary?, onClick: (() -> Void)?) {
        guard let summary else {
            threadSummaryView?.isHidden = true
            threadSummaryView?.onClick = nil
            threadTopConstraint?.isActive = false
            threadBottomConstraint?.isActive = false
            contentBottomToRow.isActive = true
            return
        }

        if threadSummaryView == nil {
            let view = MessageThreadSummaryView()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            threadSummaryView = view
            threadHeightConstraint = view.heightAnchor.constraint(equalToConstant: 0)
            threadHeightConstraint?.isActive = true
            threadTopConstraint = view.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: Self.threadSpacing)
            threadBottomConstraint = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        }

        threadSummaryView?.configure(summary: summary)
        threadSummaryView?.onClick = onClick
        threadSummaryView?.isHidden = false
        threadHeightConstraint?.constant = MessageThreadSummaryView.height(for: summary)
        contentBottomToRow.isActive = false
        threadTopConstraint?.isActive = true
        threadBottomConstraint?.isActive = true
    }

    func configureReply(details: EmbeddedEventDetails?, onClick: (() -> Void)?) {
        replyDetails = details
        guard let details else {
            replyPreview?.isHidden = true
            replyPreview?.onClick = nil
            contentTopToReply?.isActive = false
            contentTopToRow.isActive = true
            return
        }

        if replyPreview == nil {
            let preview = MessageReplyPreviewView()
            preview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                preview.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ])
            replyPreview = preview
            replyHeightConstraint = preview.heightAnchor.constraint(equalToConstant: 28)
            replyHeightConstraint?.isActive = true
            contentTopToReply = contentView.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: Self.replySpacing)
        }

        replyPreview?.configure(details: details)
        replyPreview?.onClick = onClick
        replyPreview?.isHidden = false
        contentTopToRow.isActive = false
        contentTopToReply?.isActive = true
        updateReplyHeight()
    }

    override func layout() {
        super.layout()
        updateReplyHeight()
    }

    private func updateReplyHeight() {
        guard let replyDetails, bounds.width > 0 else { return }
        let height = MessageReplyPreviewView.height(for: replyDetails, width: max(bounds.width - Self.contentHorizontalInset, 1))
        if replyHeightConstraint?.constant != height {
            replyHeightConstraint?.constant = height
        }
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

    func height(for content: MsgLikeContent, width: CGFloat, replyDetails: EmbeddedEventDetails?) -> CGFloat {
        let contentWidth = max(width - Self.contentHorizontalInset, 1)
        let replyHeight = replyDetails.map {
            MessageReplyPreviewView.height(for: $0, width: contentWidth) + Self.replySpacing
        } ?? 0
        let threadHeight = content.threadSummary.map {
            MessageThreadSummaryView.height(for: $0) + Self.threadSpacing
        } ?? 0
        return max(ceil(contentView.height(for: content, width: contentWidth)) + replyHeight + threadHeight + 8, 28)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

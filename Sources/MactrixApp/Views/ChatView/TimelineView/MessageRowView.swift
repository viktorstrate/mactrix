import AppKit
import MatrixRustSDK
import MatrixProtocols
import MactrixUI
import MatrixIntegration

/// Shared row chrome. The content view is created once and retained across table reuse.
final class MessageRowView: NSView {
    let contentKind: MessageContentKind
    var onHoverChange: ((MessageRowView, Bool, NSEvent) -> Bool)?
    var onSelectRequest: ((MessageRowView) -> Void)?
    var onArrowKey: ((TimelineSelectionDirection) -> Void)?
    private var isHovered = false
    private var isMessageSelected = false

    private static let contentHorizontalInset: CGFloat = 74
    private static let replySpacing: CGFloat = 20
    private static let threadSpacing: CGFloat = 10
    private static let reactionSpacing: CGFloat = 10
    private static let receiptSpacing: CGFloat = 10

    private let timestamp = NSTextField(labelWithString: "")
    private let contentView: any MessageContentRowView
    private var replyPreview: MessageReplyPreviewView?
    private var replyDetails: MatrixRustSDK.EmbeddedEventDetails?
    private var replyHeightConstraint: NSLayoutConstraint?

    private var contentTopToReply: NSLayoutConstraint?
    private lazy var contentTopToRow = contentView.topAnchor.constraint(equalTo: topAnchor, constant: 4)
    private lazy var contentBottomToRow = contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)

    private var threadSummaryView: MessageThreadSummaryView?
    private var threadHeightConstraint: NSLayoutConstraint?
    private var threadTopConstraint: NSLayoutConstraint?
    private var threadBottomConstraint: NSLayoutConstraint?

    private var reactionsView: MessageReactionsView?
    private var reactionsHeightConstraint: NSLayoutConstraint?
    private var reactionsTopToContent: NSLayoutConstraint?
    private var reactionsTopToThread: NSLayoutConstraint?
    private var reactionsBottomToRow: NSLayoutConstraint?
    private var reactionsTrailingToContent: NSLayoutConstraint?
    private var reactionsTrailingToReceipts: NSLayoutConstraint?
    private var reactions: [MatrixRustSDK.Reaction] = []

    private var receiptsView: MessageReadReceiptsView?
    private var receiptsWidthConstraint: NSLayoutConstraint?
    private var receiptsTopToContent: NSLayoutConstraint?
    private var receiptsTopToThread: NSLayoutConstraint?
    private var receiptsTopToReactions: NSLayoutConstraint?
    private var receiptsBottomToRow: NSLayoutConstraint?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(contentKind: MessageContentKind, contentView: any MessageContentRowView, frame frameRect: NSRect = .zero) {
        self.contentKind = contentKind
        self.contentView = contentView
        super.init(frame: frameRect)

        timestamp.font = .systemFont(ofSize: NSFont.labelFontSize)
        timestamp.textColor = .secondaryLabelColor
        timestamp.alignment = .right
        timestamp.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onSelectRequest = { [weak self] in
            guard let self else { return }
            self.onSelectRequest?(self)
        }
        contentView.onArrowKey = { [weak self] direction in
            self?.onArrowKey?(direction)
        }

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
        // NSTableView may retain an old encapsulated height while a reused row is reconfigured.
        contentBottomToRow.priority = .init(999)
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

    func configure(
        event: MatrixRustSDK.EventTimelineItem,
        content: MatrixRustSDK.MsgLikeContent,
        replyDetails: MatrixRustSDK.EmbeddedEventDetails?,
        onReplyClick: (() -> Void)?,
        onThreadClick: (() -> Void)?,
        ownUserId: String?,
        onReactionClick: ((String) -> Void)?,
        roomMembers: [MatrixRustSDK.RoomMember],
        matrixClient: MatrixClient?,
        onFocusUser: ((String) -> Void)?
    ) {
        // A reused row may still have its previous table height while its content changes.
        contentBottomToRow.isActive = false
        threadBottomConstraint?.isActive = false
        reactionsBottomToRow?.isActive = false
        receiptsBottomToRow?.isActive = false

        let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
        timestamp.stringValue = Self.timeFormatter.string(from: date)
        contentView.configure(content: content, matrixClient: matrixClient)
        configureReply(details: replyDetails, onClick: onReplyClick)
        configureThread(summary: content.threadSummary, onClick: onThreadClick)
        configureReactions(content.reactions, ownUserId: ownUserId, onClick: onReactionClick)
        configureReceipts(event.userReadReceipts, roomMembers: roomMembers, imageLoader: matrixClient, onFocusUser: onFocusUser)
        isHovered = false
        updateBackground()
    }

    private func configureThread(summary: MatrixRustSDK.ThreadSummary?, onClick: (() -> Void)?) {
        guard let summary else {
            threadSummaryView?.isHidden = true
            threadSummaryView?.onClick = nil
            threadTopConstraint?.isActive = false
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
            threadBottomConstraint?.priority = .init(999)
            if let reactionsView {
                reactionsTopToThread = reactionsView.topAnchor.constraint(equalTo: view.bottomAnchor, constant: Self.reactionSpacing)
            }
            if let receiptsView {
                receiptsTopToThread = receiptsView.topAnchor.constraint(equalTo: view.bottomAnchor, constant: Self.receiptSpacing)
            }
        }

        threadSummaryView?.configure(summary: summary)
        threadSummaryView?.onClick = onClick
        threadSummaryView?.isHidden = false
        threadHeightConstraint?.constant = MessageThreadSummaryView.height(for: summary)
        threadTopConstraint?.isActive = true
    }

    private func configureReactions(_ reactions: [MatrixRustSDK.Reaction], ownUserId: String?, onClick: ((String) -> Void)?) {
        self.reactions = reactions
        if !reactions.isEmpty, reactionsView == nil {
            let view = MessageReactionsView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
            reactionsTrailingToContent = view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            reactionsView = view
            reactionsHeightConstraint = view.heightAnchor.constraint(equalToConstant: 0)
            reactionsHeightConstraint?.isActive = true
            reactionsTopToContent = view.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: Self.reactionSpacing)
            if let threadSummaryView {
                reactionsTopToThread = view.topAnchor.constraint(equalTo: threadSummaryView.bottomAnchor, constant: Self.reactionSpacing)
            }
            reactionsBottomToRow = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
            reactionsBottomToRow?.priority = .init(999)
            if let receiptsView {
                receiptsTopToReactions = receiptsView.topAnchor.constraint(equalTo: view.topAnchor, constant: 5)
                reactionsTrailingToReceipts = view.trailingAnchor.constraint(equalTo: receiptsView.leadingAnchor, constant: -Self.receiptSpacing)
            }
        }

        reactionsView?.configure(reactions: reactions, ownUserId: ownUserId)
        reactionsView?.onReactionClick = onClick
        reactionsView?.isHidden = reactions.isEmpty

        reactionsTopToContent?.isActive = false
        reactionsTopToThread?.isActive = false

        if !reactions.isEmpty {
            (threadSummaryView?.isHidden == false ? reactionsTopToThread : reactionsTopToContent)?.isActive = true
            updateReactionsHeight()
        }
    }

    private func configureReceipts(_ receipts: [String: MatrixProtocols.Receipt], roomMembers: [MatrixRustSDK.RoomMember], imageLoader: MactrixUI.ImageLoader?, onFocusUser: ((String) -> Void)?) {
        if !receipts.isEmpty, receiptsView == nil {
            let view = MessageReadReceiptsView()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            receiptsView = view
            NSLayoutConstraint.activate([
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                view.heightAnchor.constraint(equalToConstant: MessageReadReceiptsView.rowHeight),
            ])
            receiptsWidthConstraint = view.widthAnchor.constraint(equalToConstant: 0)
            receiptsWidthConstraint?.isActive = true
            receiptsTopToContent = view.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: Self.receiptSpacing)
            if let threadSummaryView {
                receiptsTopToThread = view.topAnchor.constraint(equalTo: threadSummaryView.bottomAnchor, constant: Self.receiptSpacing)
            }
            if let reactionsView {
                receiptsTopToReactions = view.topAnchor.constraint(equalTo: reactionsView.topAnchor, constant: 5)
                reactionsTrailingToReceipts = reactionsView.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: -Self.receiptSpacing)
            }
            receiptsBottomToRow = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
            // NSTableView can briefly keep the old row height while configuring a reused view.
            receiptsBottomToRow?.priority = .init(999)
        }

        receiptsView?.isHidden = receipts.isEmpty
        receiptsView?.onFocusUser = onFocusUser
        if !receipts.isEmpty {
            receiptsView?.configure(receipts: receipts, members: roomMembers, imageLoader: imageLoader)
            receiptsWidthConstraint?.constant = MessageReadReceiptsView.width(for: receipts.count)
        }

        contentBottomToRow.isActive = false
        threadBottomConstraint?.isActive = false
        reactionsBottomToRow?.isActive = false
        receiptsTopToContent?.isActive = false
        receiptsTopToThread?.isActive = false
        receiptsTopToReactions?.isActive = false
        receiptsBottomToRow?.isActive = false
        let trailingConstraints = [reactionsTrailingToContent, reactionsTrailingToReceipts].compactMap { $0 }
        NSLayoutConstraint.deactivate(trailingConstraints)
        (receipts.isEmpty || reactions.isEmpty ? reactionsTrailingToContent : reactionsTrailingToReceipts)?.isActive = true

        if receipts.isEmpty {
            if !reactions.isEmpty {
                reactionsBottomToRow?.isActive = true
            } else if threadSummaryView?.isHidden == false {
                threadBottomConstraint?.isActive = true
            } else {
                contentBottomToRow.isActive = true
            }
        } else {
            if !reactions.isEmpty {
                receiptsTopToReactions?.isActive = true
                reactionsBottomToRow?.isActive = true
            } else if threadSummaryView?.isHidden == false {
                receiptsTopToThread?.isActive = true
                receiptsBottomToRow?.isActive = true
            } else {
                receiptsTopToContent?.isActive = true
                receiptsBottomToRow?.isActive = true
            }
        }
        updateReactionsHeight()
    }

    func configureReply(details: MatrixRustSDK.EmbeddedEventDetails?, onClick: (() -> Void)?) {
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
        updateReactionsHeight()
    }

    private func updateReplyHeight() {
        guard let replyDetails, bounds.width > 0 else { return }
        let height = MessageReplyPreviewView.height(for: replyDetails, width: max(bounds.width - Self.contentHorizontalInset, 1))
        if replyHeightConstraint?.constant != height {
            replyHeightConstraint?.constant = height
        }
    }

    private func updateReactionsHeight() {
        guard !reactions.isEmpty, bounds.width > 0 else { return }
        let receiptWidth = receiptsView?.isHidden == false
            ? MessageReadReceiptsView.width(for: receiptsView?.receiptCount ?? 0) + Self.receiptSpacing : 0
        let height = MessageReactionsView.height(for: reactions, width: max(bounds.width - Self.contentHorizontalInset - receiptWidth, 1))
        if reactionsHeightConstraint?.constant != height {
            reactionsHeightConstraint?.constant = height
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if onHoverChange?(self, true, event) ?? true {
            setHoverHighlight(true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelectRequest?(self)
        super.mouseDown(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoverHighlight(onHoverChange?(self, false, event) ?? false)
    }

    func setHoverHighlight(_ highlighted: Bool) {
        isHovered = highlighted
        updateBackground()
    }

    func setSelected(_ selected: Bool) {
        isMessageSelected = selected
        updateBackground()
    }

    private func updateBackground() {
        if isMessageSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            layer?.backgroundColor = isHovered ? .init(gray: 0.5, alpha: 0.1) : nil
        }
    }

    func height(for content: MatrixRustSDK.MsgLikeContent, width: CGFloat, replyDetails: MatrixRustSDK.EmbeddedEventDetails?, receiptCount: Int) -> CGFloat {
        let contentWidth = max(width - Self.contentHorizontalInset, 1)
        let replyHeight = replyDetails.map {
            MessageReplyPreviewView.height(for: $0, width: contentWidth) + Self.replySpacing
        } ?? 0
        let threadHeight = content.threadSummary.map {
            MessageThreadSummaryView.height(for: $0) + Self.threadSpacing
        } ?? 0
        let availableReactionWidth = contentWidth - (receiptCount > 0 ? MessageReadReceiptsView.width(for: receiptCount) + Self.receiptSpacing : 0)
        let reactionsHeight = content.reactions.isEmpty ? 0 :
            MessageReactionsView.height(for: content.reactions, width: max(availableReactionWidth, 1)) + Self.reactionSpacing
        let receiptsHeight = receiptCount == 0 || !content.reactions.isEmpty ? 0 : MessageReadReceiptsView.rowHeight + Self.receiptSpacing
        return max(ceil(contentView.height(for: content, width: contentWidth)) + replyHeight + threadHeight + reactionsHeight + receiptsHeight + 8, 28)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

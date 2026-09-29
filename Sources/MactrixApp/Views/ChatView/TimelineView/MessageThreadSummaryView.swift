import AppKit
import MatrixRustSDK

/// A reusable button for opening the replies to a message.
final class MessageThreadSummaryView: NSButton {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let heading = NSTextField(labelWithString: "")
    private let snippet = NSTextField(labelWithString: "")

    private static let font = NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask
    )
    private static let lineHeight = ceil(NSFont.systemFont(ofSize: 13).boundingRectForFont.height)
    private static let padding: CGFloat = 8
    private static let lineSpacing: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        isBordered = false
        title = ""
        target = self
        action = #selector(activate)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor

        icon.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        for field in [heading, snippet] {
            field.font = Self.font
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        snippet.textColor = .secondaryLabelColor

        addSubview(icon)
        addSubview(heading)
        addSubview(snippet)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            icon.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            heading.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),

            snippet.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            snippet.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            snippet.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: Self.lineSpacing),
        ])
    }

    func configure(summary: ThreadSummary) {
        heading.stringValue = "Thread (\(summary.numReplies()) messages)"
        snippet.stringValue = summary.description ?? ""
        snippet.isHidden = summary.description == nil
    }

    static func height(for summary: ThreadSummary) -> CGFloat {
        padding * 2 + lineHeight * (summary.description == nil ? 1 : 2)
            + (summary.description == nil ? 0 : lineSpacing)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.6
        window?.displayIfNeeded()
        super.mouseDown(with: event)
        alphaValue = 1
    }

    @objc private func activate(_ sender: NSButton) {
        onClick?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

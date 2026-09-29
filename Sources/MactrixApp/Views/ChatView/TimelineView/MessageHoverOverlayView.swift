import AppKit

/// The action bar shown above the hovered message row.
final class MessageHoverOverlayView: NSView {
    enum Action {
        case reaction(String)
        case reactionPicker
        case reply
        case replyInThread
        case pin
    }

    var onAction: ((Action) -> Void)?
    var onMouseExited: ((NSEvent) -> Void)?

    private let stack = NSStackView()
    private let replyButton = HoverActionButton(symbol: "arrowshape.turn.up.left", label: "Reply")
    private let threadButton = HoverActionButton(symbol: "ellipsis.message", label: "Reply in thread")

    init() {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        updateAppearance()
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            return shadow
        }()

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for emoji in ["👍", "🎉", "❤️"] {
            let button = HoverActionButton(emoji: emoji, label: "React with \(emoji)")
            button.onClick = { [weak self] in self?.onAction?(.reaction(emoji)) }
            stack.addArrangedSubview(button)
        }

        let dividerContainer = NSView()
        dividerContainer.translatesAutoresizingMaskIntoConstraints = false
        dividerContainer.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dividerContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        dividerContainer.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.centerXAnchor.constraint(equalTo: dividerContainer.centerXAnchor),
            divider.centerYAnchor.constraint(equalTo: dividerContainer.centerYAnchor),
            divider.heightAnchor.constraint(equalToConstant: 18),
        ])
        stack.addArrangedSubview(dividerContainer)

        let reactionPicker = HoverActionButton(symbol: "face.smiling", label: "React")
        reactionPicker.onClick = { [weak self] in self?.onAction?(.reactionPicker) }
        stack.addArrangedSubview(reactionPicker)

        replyButton.onClick = { [weak self] in self?.onAction?(.reply) }
        threadButton.onClick = { [weak self] in self?.onAction?(.replyInThread) }
        stack.addArrangedSubview(replyButton)
        stack.addArrangedSubview(threadButton)

        let pinButton = HoverActionButton(symbol: "pin", label: "Pin")
        pinButton.onClick = { [weak self] in self?.onAction?(.pin) }
        stack.addArrangedSubview(pinButton)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        configure(canReply: true)
    }

    func configure(canReply: Bool) {
        replyButton.isHidden = !canReply
        threadButton.isHidden = !canReply
        setFrameSize(fittingSize)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?(event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HoverActionButton: NSButton {
    var onClick: (() -> Void)?
    private var isHovered = false
    private var symbolView: NSImageView?
    private let hoverBackground = CALayer()

    init(emoji: String, label: String) {
        super.init(frame: .zero)
        title = emoji
        font = .systemFont(ofSize: 13)
        configure(label: label)
    }

    init(symbol: String, label: String) {
        super.init(frame: .zero)
        configure(label: label)

        title = ""

        // NSButton.image makes AppKit grow the button to the symbol's cell height.
        // Keep the symbol separate so AppKit does not change the button's hit area.
        let symbolView = NSImageView()
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.contentTintColor = .labelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),
        ])
        self.symbolView = symbolView
    }

    private func configure(label: String) {
        isBordered = false
        toolTip = label
        setAccessibilityLabel(label)
        contentTintColor = .labelColor
        wantsLayer = true
        hoverBackground.cornerRadius = 4
        layer?.insertSublayer(hoverBackground, at: 0)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        target = self
        action = #selector(clicked)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        contentTintColor = isHovered ? .controlAccentColor : .labelColor
        symbolView?.contentTintColor = contentTintColor
        hoverBackground.backgroundColor = isHovered
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : nil
    }

    override func layout() {
        super.layout()
        hoverBackground.frame = bounds.insetBy(dx: 2, dy: 4)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep the image view from intercepting the button's target/action click.
        super.hitTest(point) == nil ? nil : self
    }

    @objc private func clicked() {
        onClick?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

import AppKit
import QuartzCore

final class TypingIndicatorRowView: NSView {
    static let rowHeight: Double = 32

    private let label = NSTextField(labelWithString: "")
    private let dots = (0 ..< 3).map { _ in NSView() }
    private let content = NSStackView()
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let dotStack = NSStackView(views: dots)
        dotStack.orientation = .horizontal
        dotStack.alignment = .centerY
        dotStack.spacing = 2

        for dot in dots {
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            dot.layer?.cornerRadius = 3
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
            ])
        }

        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.addArrangedSubview(dotStack)
        content.addArrangedSubview(label)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isHidden = true
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(names: [String]) {
        guard !names.isEmpty else {
            label.stringValue = ""
            content.isHidden = true
            stopAnimating()
            return
        }

        let text = NSMutableAttributedString(
            string: names.joined(separator: ", "),
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        text.append(NSAttributedString(
            string: String(localized: names.count == 1 ? " is typing" : " are typing"),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        ))
        label.attributedStringValue = text
        content.isHidden = false
        startAnimating()
    }

    private func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        for (index, dot) in dots.enumerated() {
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.2, 0.7, 0.2]
            opacity.keyTimes = [0, 0.5, 1]
            opacity.duration = 1.8
            opacity.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            opacity.repeatCount = .infinity
            dot.layer?.add(opacity, forKey: "typingPulse")
        }
    }

    private func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        for dot in dots {
            dot.layer?.removeAnimation(forKey: "typingPulse")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

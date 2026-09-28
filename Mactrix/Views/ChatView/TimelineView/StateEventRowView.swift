import AppKit
import MatrixRustSDK

final class StateEventRowView: NSView {
    private let timestamp = NSTextField(labelWithString: "")
    private let descriptionField = NSTextField(labelWithString: "")

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

        descriptionField.isSelectable = true
        descriptionField.usesSingleLineMode = false
        descriptionField.lineBreakMode = .byWordWrapping
        descriptionField.maximumNumberOfLines = 0
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        descriptionField.allowsEditingTextAttributes = true

        addSubview(timestamp)
        addSubview(descriptionField)
        NSLayoutConstraint.activate([
            timestamp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            timestamp.widthAnchor.constraint(equalToConstant: 32 + 16),

            descriptionField.leadingAnchor.constraint(equalTo: timestamp.trailingAnchor, constant: 16),
            descriptionField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            descriptionField.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            descriptionField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
        ])
    }

    func configure(event: EventTimelineItem) {
        let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
        timestamp.stringValue = Self.timeFormatter.string(from: date)
        descriptionField.attributedStringValue = Self.attributedDescription(for: event)
    }

    static func height(for event: EventTimelineItem, width: CGFloat) -> CGFloat {
        let textWidth = max(width - 74, 1)
        let textHeight = attributedDescription(for: event).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(ceil(textHeight), 28)
    }

    private static func attributedDescription(for event: EventTimelineItem) -> NSAttributedString {
        let color = NSColor.secondaryLabelColor
        let size = NSFont.systemFontSize
        let result = NSMutableAttributedString(string: event.sender, attributes: [
            .font: NSFont.boldSystemFont(ofSize: size),
            .foregroundColor: color,
        ])
        result.append(NSAttributedString(string: ": ", attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
        ]))
        result.append(NSAttributedString(string: event.content.description, attributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask),
            .foregroundColor: color,
        ]))
        return result
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

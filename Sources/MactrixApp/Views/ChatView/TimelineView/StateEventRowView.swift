import AppKit
import MatrixRustSDK

final class StateEventRowView: NSView {
  private let timestamp = NSTextField(labelWithString: "")
  private let descriptionField = NSTextField(labelWithString: "")
  private let expandButton = NSButton()

  private var expanded = false
  private var items: [TimelineItemRowInfo.StateEntry] = []

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    expandButton.target = self
    expandButton.action = #selector(toggleExpand)
    expandButton.isBordered = false
    expandButton.contentTintColor = .linkColor
    expandButton.translatesAutoresizingMaskIntoConstraints = false
    updateExpandButtonTitle()

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
    addSubview(expandButton)

    NSLayoutConstraint.activate([
      timestamp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      timestamp.widthAnchor.constraint(equalToConstant: 32 + 16),

      descriptionField.leadingAnchor.constraint(equalTo: timestamp.trailingAnchor, constant: 16),
      descriptionField.trailingAnchor.constraint(
        equalTo: expandButton.leadingAnchor, constant: -10),
      descriptionField.topAnchor.constraint(equalTo: topAnchor, constant: 0),
      descriptionField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),

      expandButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      expandButton.topAnchor.constraint(equalTo: topAnchor, constant: 0),
    ])

    expandButton.setContentHuggingPriority(.required, for: .horizontal)
    expandButton.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  func configure(items: [TimelineItemRowInfo.StateEntry]) {
    precondition(!items.isEmpty)
    self.items = items
    let date = Date(timeIntervalSince1970: Double(items[0].event.timestamp) / 1000)
    timestamp.stringValue = Self.timeFormatter.string(from: date)
    descriptionField.attributedStringValue = Self.attributedDescription(for: items)
  }

  @objc func toggleExpand() {
    expanded.toggle()
    updateExpandButtonTitle()
  }

  private func updateExpandButtonTitle() {
    expandButton.title = expanded ? "Collapse" : "Expand"
  }

  static func height(for items: [TimelineItemRowInfo.StateEntry], width: CGFloat) -> CGFloat {
    let textWidth = max(width - 74, 1)
    let textHeight = attributedDescription(for: items).boundingRect(
      with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height
    return max(ceil(textHeight), 28)
  }

  private static func attributedDescription(for items: [TimelineItemRowInfo.StateEntry])
    -> NSAttributedString
  {
    let color = NSColor.secondaryLabelColor
    let size = NSFont.systemFontSize
    let result = NSMutableAttributedString()

    let summary = StateEventSummaryFormatter.summary(for: items.map(\.event))
    let bodyFont = NSFontManager.shared.convert(
      NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    for segment in summary.segments {
      result.append(
        NSAttributedString(
          string: segment.text,
          attributes: [
            .font: segment.isName ? NSFont.boldSystemFont(ofSize: size) : bodyFont,
            .foregroundColor: color,
          ]))
    }

    return result
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

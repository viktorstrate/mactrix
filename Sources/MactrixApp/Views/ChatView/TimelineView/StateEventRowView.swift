import AppKit
import MatrixRustSDK
import Utils

final class StateEventRowView: NSView {
  @MainActor private enum Layout {
    static var timestampWidth: CGFloat { TimelineTypography.scaled(48) }
    static let timestampGap: CGFloat = 16
    static let buttonGap: CGFloat = 10
    static let trailingInset: CGFloat = 10
    static let verticalInset: CGFloat = 2
    static let detailSpacing: CGFloat = 4
    static var minimumLineHeight: CGFloat { max(24, ceil(TimelineTypography.scaled(24))) }
    static var buttonWidth: CGFloat {
      let button = NSButton()
      button.isBordered = false
      button.font = .systemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
      button.title = "Expand"
      let expand = button.intrinsicContentSize.width
      button.title = "Collapse"
      return ceil(max(expand, button.intrinsicContentSize.width))
    }
  }

  private let stack = NSStackView()
  private let expandButton = NSButton()
  private var lines: [EventLineView] = []
  private var lineHeights: [NSLayoutConstraint] = []
  private var measuredTextWidth: CGFloat?
  private var stackTrailing: NSLayoutConstraint!
  private var buttonWidth: NSLayoutConstraint!
  private var onToggleExpanded: (() -> Void)?
  private var showsButton = false

  override var isFlipped: Bool { true }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    clipsToBounds = true
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Layout.detailSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false

    expandButton.target = self
    expandButton.action = #selector(toggleExpand)
    expandButton.isBordered = false
    expandButton.contentTintColor = .linkColor
    expandButton.translatesAutoresizingMaskIntoConstraints = false
    expandButton.setContentCompressionResistancePriority(.required, for: .horizontal)

    addSubview(stack)
    addSubview(expandButton)
    stackTrailing = stack.trailingAnchor.constraint(equalTo: trailingAnchor)
    buttonWidth = expandButton.widthAnchor.constraint(equalToConstant: Layout.buttonWidth)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
      stackTrailing,
      expandButton.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Layout.trailingInset),
      expandButton.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
      buttonWidth,
    ])
  }

  func configure(
    items: [TimelineItemRowInfo.StateEntry], expanded: Bool = false,
    onFocusUser: ((String) -> Void)? = nil,
    onToggleExpanded: (() -> Void)? = nil
  ) {
    precondition(!items.isEmpty)
    self.onToggleExpanded = onToggleExpanded
    expandButton.font = .systemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
    buttonWidth.constant = Layout.buttonWidth
    showsButton = items.count > 1
    let expanded = expanded && showsButton
    expandButton.isHidden = !showsButton
    expandButton.title = expanded ? "Collapse" : "Expand"
    expandButton.setAccessibilityLabel(expanded ? "Collapse state changes" : "Expand state changes")
    expandButton.setAccessibilityExpanded(expanded)
    stackTrailing.constant = -Self.trailingSpace(showsButton: showsButton)

    // Remove, rather than merely hide, details so reuse and accessibility cannot
    // expose entries from a previous configuration.
    NSLayoutConstraint.deactivate(lineHeights)
    for line in lines {
      stack.removeArrangedSubview(line)
      line.removeFromSuperview()
    }
    lines = []
    lineHeights = []
    measuredTextWidth = nil
    let descriptions = Self.descriptions(for: items, expanded: expanded)
    for (index, description) in descriptions.enumerated() {
      let event = items[expanded ? index : 0].event
      let line = EventLineView()
      let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
      line.timestamp.stringValue = Self.timeFormatter.string(from: date)
      line.descriptionField.attributedStringValue = description
      line.descriptionField.onFocusUser = onFocusUser
      stack.addArrangedSubview(line)
      let height = line.heightAnchor.constraint(equalToConstant: Layout.minimumLineHeight)
      NSLayoutConstraint.activate([
        line.widthAnchor.constraint(equalTo: stack.widthAnchor), height,
      ])
      lines.append(line)
      lineHeights.append(height)
    }
    updateLineHeights()
    needsLayout = true
  }

  @objc private func toggleExpand() {
    onToggleExpanded?()
  }

  override func layout() {
    updateLineHeights()
    super.layout()
  }

  private func updateLineHeights() {
    let textWidth = Self.textWidth(width: bounds.width, showsButton: showsButton)
    guard measuredTextWidth != textWidth else { return }
    measuredTextWidth = textWidth
    for (line, constraint) in zip(lines, lineHeights) {
      let height = Self.textHeight(line.descriptionField.attributedStringValue, width: textWidth)
      if constraint.constant != height { constraint.constant = height }
    }
  }

  static func height(
    for items: [TimelineItemRowInfo.StateEntry], width: CGFloat, expanded: Bool = false
  ) -> CGFloat {
    guard !items.isEmpty else { return Layout.minimumLineHeight + 2 * Layout.verticalInset }
    let descriptions = descriptions(for: items, expanded: expanded && items.count > 1)
    let textWidth = textWidth(width: width, showsButton: items.count > 1)
    return descriptions.reduce(2 * Layout.verticalInset) {
      $0 + textHeight($1, width: textWidth)
    } + CGFloat(descriptions.count - 1) * Layout.detailSpacing
  }

  private static func trailingSpace(showsButton: Bool) -> CGFloat {
    Layout.trailingInset + (showsButton ? Layout.buttonGap + Layout.buttonWidth : 0)
  }

  private static func textWidth(width: CGFloat, showsButton: Bool) -> CGFloat {
    max(
      width - Layout.timestampWidth - Layout.timestampGap - trailingSpace(showsButton: showsButton),
      1)
  }

  private static let measuringField = makeDescriptionField()

  private static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    measuringField.attributedStringValue = text
    let size = measuringField.cell!.cellSize(
      forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
    return max(ceil(size.height), Layout.minimumLineHeight)
  }

  private static func makeDescriptionField() -> MessageTextField {
    let field = MessageTextField(wrappingLabelWithString: "")
    field.isSelectable = true
    field.maximumNumberOfLines = 0
    field.allowsEditingTextAttributes = true
    field.translatesAutoresizingMaskIntoConstraints = false
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  private static func descriptions(
    for items: [TimelineItemRowInfo.StateEntry], expanded: Bool
  ) -> [NSAttributedString] {
    if expanded || items.count == 1 {
      return items.map { fullDescription(for: $0.event) }
    }
    let summary = StateEventSummaryFormatter.summary(for: items.map(\.event))
    let result = NSMutableAttributedString()
    for segment in summary.segments {
      result.append(
        attributedText(segment.text, userId: segment.userId))
    }
    return [result]
  }

  private static func fullDescription(for event: EventTimelineItem) -> NSAttributedString {
    let name = event.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? event.sender
    let result = NSMutableAttributedString(
      attributedString: attributedText(name, userId: event.sender))
    result.append(attributedText(" " + event.content.userInterfaceText))
    return result
  }

  private static func attributedText(
    _ text: String, userId: String? = nil
  ) -> NSAttributedString {
    let isName = userId != nil
    let size = TimelineTypography.scaled(NSFont.systemFontSize)
    let font =
      isName
      ? NSFont.boldSystemFont(ofSize: size)
      : NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor.secondaryLabelColor,
    ]
    if isName, let userId,
      let identifier = userId.dropFirst().addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))),
      let url = URL(string: "matrix:u/" + identifier)
    {
      attributes[.link] = url
    }
    return NSAttributedString(string: text, attributes: attributes)
  }

  private final class EventLineView: NSView {
    let timestamp = NSTextField(labelWithString: "")
    let descriptionField = StateEventRowView.makeDescriptionField()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      translatesAutoresizingMaskIntoConstraints = false
      timestamp.font = .systemFont(ofSize: TimelineTypography.scaled(NSFont.labelFontSize))
      timestamp.textColor = .secondaryLabelColor
      timestamp.alignment = .right
      timestamp.translatesAutoresizingMaskIntoConstraints = false
      addSubview(timestamp)
      addSubview(descriptionField)
      NSLayoutConstraint.activate([
        timestamp.leadingAnchor.constraint(equalTo: leadingAnchor),
        timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 2),
        timestamp.widthAnchor.constraint(equalToConstant: Layout.timestampWidth),
        descriptionField.leadingAnchor.constraint(
          equalTo: timestamp.trailingAnchor, constant: Layout.timestampGap),
        descriptionField.trailingAnchor.constraint(equalTo: trailingAnchor),
        descriptionField.topAnchor.constraint(equalTo: topAnchor),
        descriptionField.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// NSTextField is the delegate of its field editor; handle links before AppKit opens them externally.
final class MessageTextField: NSTextField, NSTextViewDelegate {
  var onFocusUser: ((String) -> Void)?

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL,
      let uri = try? MatrixUriScheme(parseUrl: url.absoluteString),
      case .user(let userId) = uri.kind, uri.action == nil,
      let onFocusUser
    else { return false }
    onFocusUser(userId)
    return true
  }
}

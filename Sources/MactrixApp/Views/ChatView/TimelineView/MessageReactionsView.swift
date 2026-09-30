import AppKit
import MatrixRustSDK

/// Keeps reaction buttons alive when a table row is reused.
final class MessageReactionsView: NSView {
  var onReactionClick: ((String) -> Void)?

  private var buttons: [ReactionButton] = []
  private var reactions: [Reaction] = []

  private static let rowHeight: CGFloat = 28
  private static let spacing: CGFloat = 6

  override var isFlipped: Bool {
    true
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  func configure(reactions: [Reaction], ownUserId: String?) {
    self.reactions = reactions
    while buttons.count < reactions.count {
      let reaction = reactions[buttons.count]
      let button = ReactionButton(
        frame: NSRect(
          x: 0, y: 0, width: ReactionButton.width(for: reaction), height: Self.rowHeight
        ))
      button.onClick = { [weak self] key in self?.onReactionClick?(key) }
      addSubview(button)
      buttons.append(button)
    }
    for (button, reaction) in zip(buttons, reactions) {
      button.configure(reaction: reaction, ownUserId: ownUserId)
      button.isHidden = false
    }
    for button in buttons.dropFirst(reactions.count) {
      button.isHidden = true
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    var x: CGFloat = 0
    var y: CGFloat = 0
    for (reaction, button) in zip(reactions, buttons) {
      let width = ReactionButton.width(for: reaction)
      if x > 0, x + width > bounds.width {
        x = 0
        y += Self.rowHeight + Self.spacing
      }
      button.frame = NSRect(x: x, y: y, width: width, height: Self.rowHeight)
      x += width + Self.spacing
    }
  }

  static func height(for reactions: [Reaction], width: CGFloat) -> CGFloat {
    guard !reactions.isEmpty else { return 0 }
    var x: CGFloat = 0
    var rows = 1
    for reaction in reactions {
      let buttonWidth = ReactionButton.width(for: reaction)
      if x > 0 && x + buttonWidth > width {
        x = 0
        rows += 1
      }
      x += buttonWidth + spacing
    }
    return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class ReactionButton: NSButton {
  var onClick: ((String) -> Void)?
  private var reactionKey = ""
  private let label = NSTextField(labelWithString: "")
  private static let font = NSFont.systemFont(ofSize: 13)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    title = ""
    target = self
    action = #selector(activate)
    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.borderWidth = 1

    label.font = Self.font
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func configure(reaction: Reaction, ownUserId: String?) {
    reactionKey = reaction.key
    label.stringValue = "\(reaction.key)  \(reaction.senders.count)"
    setAccessibilityLabel(label.stringValue)
    toolTip = "Reacted by " + reaction.senders.prefix(5).map(\.senderId).joined(separator: ", ")
    let active = ownUserId.map { id in reaction.senders.contains { $0.senderId == id } } ?? false
    layer?.borderColor = (active ? NSColor.systemBlue : .systemGray).cgColor
    layer?.backgroundColor =
      (active ? NSColor.systemBlue : .systemGray).withAlphaComponent(0.12).cgColor
  }

  static func width(for reaction: Reaction) -> CGFloat {
    ceil(
      ("\(reaction.key)  \(reaction.senders.count)" as NSString).size(withAttributes: [.font: font])
        .width) + 16
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
    onClick?(reactionKey)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

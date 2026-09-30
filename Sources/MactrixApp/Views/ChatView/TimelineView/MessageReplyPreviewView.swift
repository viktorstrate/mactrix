import AppKit
import MatrixRustSDK

/// A reusable, clickable summary of the message being replied to.
final class MessageReplyPreviewView: NSButton {
  var onClick: (() -> Void)?
  private var isPending = false

  private let accent = NSView()
  private let name = NSTextField(labelWithString: "")
  private let message = NSTextField(labelWithString: "")

  private static let fontSize: CGFloat = 13
  private static let nameFont = NSFontManager.shared.convert(
    NSFont.boldSystemFont(ofSize: fontSize), toHaveTrait: .italicFontMask
  )
  private static let messageFont = NSFontManager.shared.convert(
    NSFont.systemFont(ofSize: fontSize), toHaveTrait: .italicFontMask
  )

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    isBordered = false
    title = ""
    target = self
    action = #selector(activate)

    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor

    accent.wantsLayer = true
    accent.layer?.cornerRadius = 1.5
    accent.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.5).cgColor
    accent.translatesAutoresizingMaskIntoConstraints = false

    for field in [name, message] {
      field.textColor = .labelColor
      field.usesSingleLineMode = false
      field.lineBreakMode = .byWordWrapping
      field.maximumNumberOfLines = 0
      field.translatesAutoresizingMaskIntoConstraints = false
    }
    name.font = Self.nameFont
    message.font = Self.messageFont

    addSubview(accent)
    addSubview(name)
    addSubview(message)
    NSLayoutConstraint.activate([
      accent.leadingAnchor.constraint(equalTo: leadingAnchor),
      accent.topAnchor.constraint(equalTo: topAnchor),
      accent.bottomAnchor.constraint(equalTo: bottomAnchor),
      accent.widthAnchor.constraint(equalToConstant: 3),

      name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      name.topAnchor.constraint(equalTo: topAnchor, constant: 4),

      message.leadingAnchor.constraint(equalTo: name.leadingAnchor),
      message.trailingAnchor.constraint(equalTo: name.trailingAnchor),
      message.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
      message.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
    ])
  }

  func configure(details: EmbeddedEventDetails) {
    let text = Self.text(for: details)
    name.stringValue = text.name
    message.stringValue = text.message
    isPending = text.isPending
    updateOpacity()
  }

  static func height(for details: EmbeddedEventDetails, width: CGFloat) -> CGFloat {
    let text = text(for: details)
    let textWidth = max(width - 20, 1)
    func height(_ string: String, font: NSFont) -> CGFloat {
      ceil(
        (string as NSString).boundingRect(
          with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading],
          attributes: [.font: font]
        ).height)
    }
    return 16 + height(text.name, font: nameFont) + height(text.message, font: messageFont)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    updateOpacity(pressed: true)
    window?.displayIfNeeded()

    // AppKit tracks the press and sends the action only for a completed click.
    // Its cell highlighting does not affect this button's custom subviews.
    super.mouseDown(with: event)

    updateOpacity()
  }

  private func updateOpacity(pressed: Bool = false) {
    alphaValue = (isPending ? 0.5 : 1) * (pressed ? 0.6 : 1)
  }

  @objc private func activate(_ sender: NSButton) {
    onClick?()
  }

  private static func text(for details: EmbeddedEventDetails) -> (
    name: String, message: String, isPending: Bool
  ) {
    switch details {
    case .unavailable, .pending:
      return ("Loading reply…", "", true)
    case .ready(let content, let sender, let senderProfile, _, _):
      let displayName: String
      if case .ready(let name, _, _, _, _) = senderProfile, let name {
        displayName = name
      } else {
        displayName = sender
      }
      return (displayName, content.userInterfaceText, false)
    case .error(let message):
      return ("Reply unavailable", message, false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

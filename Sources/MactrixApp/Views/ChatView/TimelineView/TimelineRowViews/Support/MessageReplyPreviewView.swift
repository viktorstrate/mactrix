import AppKit
import ContactLinking
import MatrixRustSDK

/// A reusable, clickable summary of the message being replied to.
final class MessageReplyPreviewView: NSButton {
  var onClick: (() -> Void)?
  private var isPending = false

  private let accent = NSView()
  private let name = NSTextField(labelWithString: "")
  private let message = NSTextField(labelWithString: "")

  private static var nameFont: NSFont {
    NSFontManager.shared.convert(
      NSFont.boldSystemFont(ofSize: TimelineTypography.fontSize), toHaveTrait: .italicFontMask)
  }
  private static var messageFont: NSFont {
    NSFontManager.shared.convert(
      NSFont.systemFont(ofSize: TimelineTypography.fontSize), toHaveTrait: .italicFontMask)
  }

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
    name.font = Self.nameFont
    message.font = Self.messageFont
    let text = Self.text(for: details)
    name.stringValue = text.name
    message.attributedStringValue = text.message
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

    let messageHeight = text.message.boundingRect(
      with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
    ).height

    return 16 + height(text.name, font: nameFont) + messageHeight
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Prevent hit testing from returning a child view to let this button handle all events.
    super.hitTest(point) == nil ? nil : self
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
    name: String, message: NSAttributedString, isPending: Bool
  ) {
    func plain(string: String) -> NSAttributedString {
      return NSAttributedString(
        string: string,
        attributes: [
          .font: Self.messageFont,
          .foregroundColor: NSColor.labelColor,
        ])
    }

    switch details {
    case .unavailable, .pending:
      return (String(localized: "Loading reply…"), plain(string: ""), true)
    case .ready(let content, let sender, let senderProfile, _, _):
      var matrixName: String?
      if case .ready(let name, _, _, _, _) = senderProfile {
        matrixName = name
      }
      let displayName = ContactDirectory.shared.resolvedName(userID: sender, matrixName: matrixName)

      // Use proper formatting only for text messages for now.
      let body: NSAttributedString
      if case .msgLike(content: let msgLike) = content,
        case .message(content: let msgContent) = msgLike.kind,
        case .text = msgContent.msgType
      {
        body = MessageTextContentView.attributedBody(for: msgLike)
      } else {
        body = plain(string: content.userInterfaceText)
      }

      return (displayName, body, false)
    case .error(let message):
      return (String(localized: "Reply unavailable"), plain(string: message), false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

import AppKit
import MatrixIntegration
import MatrixRustSDK
import MessageFormatting
import Utils

/// Retains the NSTextView and its layout machinery when its table row is reused.
final class MessageTextContentView: NSView, MessageContentRowView {
  var handleMatrixUri: ((MatrixUriScheme) -> Bool)? {
    didSet { bodyText.handleMatrixUri = handleMatrixUri }
  }
  var onSelectRequest: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  private let bodyText = OcclusionAwareTextView(frame: .zero)

  var cachedEditingView: MessageEditingView? = nil
  public var isEditing: Bool { cachedEditingView?.isEditing ?? false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    bodyText.isVerticallyResizable = true
    bodyText.onMouseDown = { [weak self] in self?.onSelectRequest?() }
    bodyText.onArrowKey = { [weak self] direction in self?.onArrowKey?(direction) }

    addSubview(bodyText)

    NSLayoutConstraint.activate([
      bodyText.leadingAnchor.constraint(equalTo: leadingAnchor),
      bodyText.trailingAnchor.constraint(equalTo: trailingAnchor),
      bodyText.topAnchor.constraint(equalTo: topAnchor),
      bodyText.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func configure(content: MatrixRustSDK.MsgLikeContent, matrixClient: MatrixClient?) {
    bodyText.textStorage?.setAttributedString(Self.attributedBody(for: content))
  }

  func configureCaption(_ caption: String?, formatted: FormattedBody?) {
    bodyText.textStorage?.setAttributedString(Self.attributedCaption(caption, formatted: formatted))
  }

  func height(forCaption caption: String?, formatted: FormattedBody?, width: CGFloat) -> CGFloat {
    if let cachedEditingView, cachedEditingView.isEditing {
      return cachedEditingView.height(for: width)
    }
    return measure(Self.attributedCaption(caption, formatted: formatted), width: width)
  }

  func height(for content: MatrixRustSDK.MsgLikeContent, width: CGFloat) -> CGFloat {
    if let cachedEditingView, cachedEditingView.isEditing {
      return cachedEditingView.height(for: width)
    }
    return measure(Self.attributedBody(for: content), width: width)
  }

  func configureEditing(_ state: MessageEditState?) {
    let editingView: MessageEditingView
    if let cachedEditingView {
      editingView = cachedEditingView
    } else {
      editingView = MessageEditingView(frame: .zero)
      cachedEditingView = editingView
      editingView.isHidden = true
      editingView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(editingView)

      NSLayoutConstraint.activate([
        editingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        editingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        editingView.topAnchor.constraint(equalTo: topAnchor),
        editingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    editingView.configureEditing(state)

    bodyText.isHidden = state != nil
    editingView.isHidden = state == nil
  }

  private func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    guard let textStorage = bodyText.textStorage,
      let layoutManager = bodyText.layoutManager,
      let textContainer = bodyText.textContainer
    else { return 20 }

    textContainer.widthTracksTextView = false
    textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    textStorage.setAttributedString(text)
    layoutManager.ensureLayout(for: textContainer)
    return layoutManager.usedRect(for: textContainer).height
  }

  private static func attributedCaption(_ caption: String?, formatted: FormattedBody?)
    -> NSAttributedString
  {
    let fontSize = TimelineTypography.fontSize
    if let formatted, formatted.format == .html {
      return attributedFormattedBody(
        formatted.body, baseFontSize: CGFloat(fontSize), color: .labelColor)
    }
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let attributed =
      (try? AttributedString(markdown: caption ?? "", options: options))
      ?? AttributedString(caption ?? "")
    let result = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
    let fullRange = NSRange(location: 0, length: result.length)
    result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
    result.enumerateAttribute(.font, in: fullRange) { font, range, _ in
      if font == nil {
        result.addAttribute(
          .font, value: NSFont.systemFont(ofSize: CGFloat(fontSize)), range: range)
      }
    }
    return result
  }

  private static func attributedBody(for content: MatrixRustSDK.MsgLikeContent)
    -> NSAttributedString
  {
    let fontSize = TimelineTypography.fontSize
    let font = NSFont.systemFont(ofSize: CGFloat(fontSize))

    func plain(_ text: String, color: NSColor = .labelColor, italic: Bool = false)
      -> NSAttributedString
    {
      NSAttributedString(
        string: text,
        attributes: [
          .font: italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font,
          .foregroundColor: color,
        ])
    }

    switch content.kind {
    case .message(let message):
      switch message.msgType {
      case .text(let text):
        return attributedText(for: text, font: font, color: .labelColor)
      case .notice(let notice):
        return attributedText(for: notice, font: font, color: .secondaryLabelColor)
      case .emote(let emote):
        return plain("Emote: \(emote.body)")
      case .audio(let audio):
        return plain("Audio: \(audio.caption ?? "no caption") \(audio.filename)")
      case .gallery(let gallery):
        return plain("Gallery: \(gallery.body)")
      case .location(let location):
        return plain("Location: \(location.body) \(location.geoUri)")
      case .other(let msgtype, let body):
        return plain("Other: \(msgtype) \(body)")
      case .image, .video, .file:
        return NSAttributedString()
      }
    case .sticker(let body, info: _, source: _):
      return plain("Sticker: \(body)")
    case .poll(
      let question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _,
      hasBeenEdited: _):
      return plain("Poll: \(question)")
    case .redacted:
      return plain("Message redacted", color: .secondaryLabelColor, italic: true)
    case .unableToDecrypt:
      return plain("Unable to decrypt", color: .secondaryLabelColor, italic: true)
    case .other(let eventType):
      return plain("Custom event: \(eventType.userInterfaceText)")
    case .liveLocation(content: let location):
      return plain("Live location: \(location.description ?? "no description")")
    }
  }

  private static func attributedText(
    for message: some MatrixIntegration.MessageContent, font: NSFont, color: NSColor
  ) -> NSAttributedString {
    if let formatted = message.formatted, formatted.format == .html {
      return attributedFormattedBody(
        formatted.body, baseFontSize: font.pointSize, color: color)
    }
    return NSAttributedString(
      string: message.body.trimmingCharacters(in: .whitespacesAndNewlines),
      attributes: [
        .font: font,
        .foregroundColor: color,
      ])
  }

  private static func attributedFormattedBody(
    _ body: String, baseFontSize: CGFloat, color: NSColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString(
      attributedString: parseFormattedBody(body, baseFontSize: baseFontSize))
    result.addAttribute(
      .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Lets a view drawn above the text own the cursor without knowing what that view is.
private final class OcclusionAwareTextView: MessageTextView {
  var onMouseDown: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  override func keyDown(with event: NSEvent) {
    if let direction = TimelineSelectionDirection(event: event), let onArrowKey {
      onArrowKey(direction)
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    onMouseDown?()
    super.mouseDown(with: event)
  }

  override func cursorUpdate(with event: NSEvent) {
    guard shouldHandlePointerEvent(event) else { return }
    super.cursorUpdate(with: event)
  }

  override func mouseMoved(with event: NSEvent) {
    // NSTextView also sets its cursor during mouse movement, independently
    // of cursorUpdate. Covered text must yield to the view above it here too.
    guard shouldHandlePointerEvent(event) else { return }
    super.mouseMoved(with: event)
  }

  private func shouldHandlePointerEvent(_ event: NSEvent) -> Bool {
    guard let window,
      let contentView = window.contentView,
      let contentSuperview = contentView.superview,
      let hitView = contentView.hitTest(contentSuperview.convert(event.locationInWindow, from: nil))
    else {
      return true
    }

    return hitView === self || hitView.isDescendant(of: self)
  }
}

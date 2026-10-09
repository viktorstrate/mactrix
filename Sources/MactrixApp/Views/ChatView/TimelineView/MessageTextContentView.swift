import AppKit
import MatrixIntegration
import MatrixRustSDK
import MessageFormatting

final class MessageEditingView: NSView, NSTextViewDelegate {
  private let editor = SubmitableTextView(frame: .zero)
  private let editorScrollView = NSScrollView()
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let editErrorLabel = NSTextField(labelWithString: "")
  private var editState: MessageEditState?
  private var restoringEditor = false

  public var isEditing: Bool { editState != nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    editor.onSubmit = self.saveEdit
    editor.isRichText = false
    editor.font = .systemFont(ofSize: 13)
    editor.isHorizontallyResizable = false
    editor.isVerticallyResizable = true
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainerInset = NSSize(width: 2, height: 5)
    editor.delegate = self
    editor.setAccessibilityLabel("Edit message")

    editorScrollView.documentView = editor
    editorScrollView.hasVerticalScroller = true
    editorScrollView.borderType = .noBorder
    editorScrollView.translatesAutoresizingMaskIntoConstraints = false

    let containerView = NSBox()
    containerView.boxType = .custom
    containerView.borderWidth = 1
    containerView.borderColor = .separatorColor
    containerView.cornerRadius = 6
    containerView.addSubview(editorScrollView)

    editorScrollView.wantsLayer = true
    editorScrollView.layer?.cornerRadius = 6
    editorScrollView.layer?.masksToBounds = true
    editorScrollView.contentView.wantsLayer = true
    editorScrollView.contentView.layer?.cornerRadius = 6
    editorScrollView.contentView.layer?.masksToBounds = true

    saveButton.target = self
    saveButton.action = #selector(saveEdit)
    saveButton.keyEquivalent = "\r"
    saveButton.keyEquivalentModifierMask = [.command]

    cancelButton.target = self
    cancelButton.action = #selector(cancelEdit)
    cancelButton.keyEquivalent = "\u{1b}"  // escape button

    editErrorLabel.textColor = .systemRed
    editErrorLabel.lineBreakMode = .byTruncatingTail
    editErrorLabel.isSelectable = true

    for view in [containerView, saveButton, cancelButton, editErrorLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }

    NSLayoutConstraint.activate([
      editorScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 1),
      editorScrollView.trailingAnchor.constraint(
        equalTo: containerView.trailingAnchor, constant: -1),
      editorScrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 1),
      editorScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -1),

      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -6),

      saveButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      saveButton.bottomAnchor.constraint(equalTo: bottomAnchor),

      cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -6),
      cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

      editErrorLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      editErrorLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: cancelButton.leadingAnchor, constant: 8),
      editErrorLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configureEditing(_ state: MessageEditState?) {
    editState = state
    guard let state else { return }
    restoringEditor = true
    if editor.string != state.text { editor.string = state.text }
    let length = (state.text as NSString).length
    let location = min(max(state.selectedRange.location, 0), length)
    editor.setSelectedRange(
      NSRange(
        location: location, length: min(max(state.selectedRange.length, 0), length - location)))
    restoringEditor = false
    editor.isEditable = !state.isSaving
    saveButton.isEnabled = !state.isSaving
    cancelButton.isEnabled = !state.isSaving
    saveButton.title = state.isSaving ? "Saving…" : "Save"
    editErrorLabel.stringValue = state.error ?? ""
    editErrorLabel.toolTip = state.error
  }

  func textDidChange(_ notification: Notification) {
    guard !restoringEditor, let state = editState else { return }
    state.text = editor.string
    state.selectedRange = editor.selectedRange()
    state.onChange?()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !restoringEditor, let state = editState else { return }
    state.selectedRange = editor.selectedRange()
  }

  @objc private func saveEdit() {
    guard let state = editState, !state.isSaving else { return }
    state.onSave?()
  }

  @objc private func cancelEdit() {
    guard let state = editState, !state.isSaving else { return }
    state.onCancel?()
  }
}

/// Retains the NSTextView and its layout machinery when its table row is reused.
final class MessageTextContentView: NSView, MessageContentRowView {
  var onSelectRequest: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  private let bodyText = OcclusionAwareTextView(frame: .zero)

  static let editingHeight: CGFloat = 140
  var cachedEditingView: MessageEditingView? = nil
  public var isEditing: Bool { cachedEditingView?.isEditing ?? false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    bodyText.isSelectable = true
    bodyText.isEditable = false
    bodyText.isRichText = true
    bodyText.drawsBackground = false
    bodyText.textContainerInset = .zero
    bodyText.textContainer?.lineFragmentPadding = 0
    bodyText.textContainer?.widthTracksTextView = true
    bodyText.isHorizontallyResizable = false
    bodyText.isVerticallyResizable = true
    bodyText.translatesAutoresizingMaskIntoConstraints = false
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
    isEditing
      ? Self.editingHeight
      : measure(Self.attributedCaption(caption, formatted: formatted), width: width)
  }

  func height(for content: MatrixRustSDK.MsgLikeContent, width: CGFloat) -> CGFloat {
    isEditing ? Self.editingHeight : measure(Self.attributedBody(for: content), width: width)
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
    let fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13
    if let formatted, formatted.format == .html {
      return parseFormattedBody(formatted.body, baseFontSize: CGFloat(fontSize))
    }
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let attributed =
      (try? AttributedString(markdown: caption ?? "", options: options))
      ?? AttributedString(caption ?? "")
    let result = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
    let fullRange = NSRange(location: 0, length: result.length)
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
    let fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13
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
      let result = NSMutableAttributedString(
        attributedString: parseFormattedBody(
          formatted.body, baseFontSize: font.pointSize
        ))
      if color == .secondaryLabelColor {
        result.addAttribute(
          .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
      }
      return result
    }
    return NSAttributedString(
      string: message.body.trimmingCharacters(in: .whitespacesAndNewlines),
      attributes: [
        .font: font,
        .foregroundColor: color,
      ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Lets a view drawn above the text own the cursor without knowing what that view is.
private final class OcclusionAwareTextView: NSTextView {
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

import AppKit
import MactrixUI
import MatrixProtocols
import MatrixRustSDK
import MessageFormatting

final class ComposerMentionTextView: DynamicTextView {
  typealias AvatarURLLookup = MentionAvatarLoader.AvatarURLLookup

  let mentionAutocomplete = ComposerMentionAutocompleteSession<MatrixRustSDK.RoomMember>()
  var mentionCandidateProvider: (() -> [MatrixRustSDK.RoomMember])?

  private let content = NSTextContentStorage()
  private var mentionInputChangeDepth = 0
  private var avatarLoader: MentionAvatarLoader?
  weak var imageLoader: ImageLoader?
  var avatarURLLookup: AvatarURLLookup? {
    didSet {
      avatarLoader = avatarURLLookup.map { MentionAvatarLoader(lookup: $0) }
      restoreMentionAvatars()
    }
  }

  init() {
    let manager = NSTextLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    content.addTextLayoutManager(manager)
    manager.textContainer = container
    super.init(frame: .zero, textContainer: container)
    isRichText = true
    importsGraphics = false
    NotificationCenter.default.addObserver(
      self, selector: #selector(mentionSelectionDidChange),
      name: NSTextView.didChangeSelectionNotification, object: self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var textContent: ComposerTextContent { Self.textContent(from: attributedString()) }

  var markdown: String { textContent.markdown }

  /// Loads draft text without registering user edits or emitting text-change notifications.
  func setMarkdown(_ markdown: String) {
    mentionAutocomplete.reset()
    mentionInputChangeDepth += 1
    defer { mentionInputChangeDepth -= 1 }
    let attributes = typingAttributes.filter { $0.key != .attachment }
    let text = NSMutableAttributedString(string: markdown, attributes: attributes)
    for mention in parseMarkdownMentions(markdown).reversed() {
      let payload = UserDragPayload(userId: mention.userID, username: mention.username)
      let attachment = MentionAttachment(payload: payload, imageLoader: imageLoader)
      text.replaceCharacters(
        in: mention.range,
        with: NSAttributedString(attachment: attachment, attributes: attributes))
    }
    content.textStorage?.setAttributedString(text)
    typingAttributes = attributes
    restoreMentionAvatars()
    invalidateIntrinsicContentSize()
    needsDisplay = true
  }

  override func didChangeText() {
    super.didChangeText()
    restoreMentionAvatars()
    updateMentionAutocomplete()
  }

  @objc private func mentionSelectionDidChange() {
    updateMentionAutocomplete()
  }

  func updateMentionAutocomplete() {
    guard mentionInputChangeDepth == 0 else { return }
    guard isEditable else {
      mentionAutocomplete.reset()
      return
    }
    mentionAutocomplete.update(
      in: attributedString(), selectedRange: selectedRange(), hasMarkedText: hasMarkedText(),
      candidates: mentionCandidateProvider?() ?? [])
  }

  func validatedMentionReplacementRange() -> NSRange? {
    guard isEditable, mentionInputChangeDepth == 0 else { return nil }
    return mentionAutocomplete.validatedReplacementRange(
      in: attributedString(), selectedRange: selectedRange(), hasMarkedText: hasMarkedText())
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    performMentionInputChange {
      super.insertText(insertString, replacementRange: replacementRange)
    }
  }

  override func setMarkedText(
    _ string: Any, selectedRange: NSRange, replacementRange: NSRange
  ) {
    performMentionInputChange {
      super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
  }

  override func unmarkText() {
    performMentionInputChange { super.unmarkText() }
  }

  private func performMentionInputChange(_ change: () -> Void) {
    // AppKit may emit selection/text notifications before a composition edit has finished.
    mentionInputChangeDepth += 1
    defer {
      mentionInputChangeDepth -= 1
      updateMentionAutocomplete()
    }
    change()
  }

  func cancelAvatarLookups() {
    avatarLoader?.cancel()
  }

  private func restoreMentionAvatars() {
    avatarLoader?.restoreAvatars(in: attributedString())
  }

  static func markdown(from text: NSAttributedString) -> String {
    textContent(from: text).markdown
  }

  static func textContent(from text: NSAttributedString) -> ComposerTextContent {
    let projection = MentionText.project(text, asMarkdown: true)
    return ComposerTextContent(
      markdown: projection.text, mentionedUserIDs: projection.mentionedUserIDs)
  }

  override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    [.mactrixComposerText] + super.readablePasteboardTypes
  }

  override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType)
    -> Bool
  {
    guard isEditable else { return false }

    let segments: [MentionClipboardSegment]
    switch type {
    case .mactrixComposerText:
      guard
        let data = pasteboard.data(forType: type),
        let decoded = MentionClipboardSegment.decode(data: data)
      else {
        return super.readSelection(from: pasteboard, type: .string)
      }
      segments = decoded
    case .mactrixUser:
      guard let payload = UserDragPayload.read(from: pasteboard) else { return false }
      segments = [.mention(payload)]
    default:
      return super.readSelection(from: pasteboard, type: type)
    }

    let attributes = typingAttributes.filter { $0.key != .attachment }
    let text = NSMutableAttributedString(string: "")
    for segment in segments {
      switch segment {
      case .text(let string):
        text.append(NSAttributedString(string: string, attributes: attributes))
      case .mention(let payload):
        text.append(
          NSAttributedString(
            attachment: MentionAttachment(payload: payload, imageLoader: imageLoader),
            attributes: attributes))
      }
    }
    insertText(text, replacementRange: selectedRange())
    typingAttributes = attributes
    return true
  }

  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
    [.mactrixComposerText, .string]
  }

  override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType)
    -> Bool
  {
    let selected = attributedString().attributedSubstring(from: selectedRange())
    return MentionText.writeSelection(selected, to: pasteboard, type: type)
  }

  override func height(for width: CGFloat) -> CGFloat {
    let font = font ?? .systemFont(ofSize: 13)
    return MentionTextLayout.height(
      for: attributedString(), width: width, inset: textContainerInset,
      lineFragmentPadding: textContainer?.lineFragmentPadding ?? 5,
      minimumLineHeight: font.ascender - font.descender + font.leading)
  }
}

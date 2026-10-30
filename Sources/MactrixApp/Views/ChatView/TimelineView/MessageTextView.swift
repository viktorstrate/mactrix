import AppKit
import Utils

/// Read-only TextKit 2 host for message text and view-backed mentions.
/// Handles Matrix links in the originating window.
class MessageTextView: NSTextView, NSTextViewDelegate, MentionAttachmentHost {
  var handleMatrixUri: ((MatrixUriScheme) -> Bool)?
  var onMouseDown: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  var allowsMentionInteraction: Bool {
    !isEditable && isSelectable && handleMatrixUri != nil
  }

  func mentionInteractionBegan() {
    onMouseDown?()
  }

  func activateMention(_ attachment: MentionAttachment) {
    guard allowsMentionInteraction else { return }
    _ = handleMatrixUri?(MatrixUriScheme(kind: .user(attachment.payload.userId)))
  }

  override func mouseDown(with event: NSEvent) {
    onMouseDown?()
    super.mouseDown(with: event)
  }

  private let content = NSTextContentStorage()

  override init(frame frameRect: NSRect) {
    let manager = NSTextLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude))
    content.addTextLayoutManager(manager)
    manager.textContainer = container
    super.init(frame: frameRect, textContainer: container)
    configure()
  }

  private func configure() {
    delegate = self
    isEditable = false
    isSelectable = true
    isRichText = true
    importsGraphics = false
    drawsBackground = false
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    isHorizontallyResizable = false
    translatesAutoresizingMaskIntoConstraints = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
    let selected = attributedString().attributedSubstring(from: selectedRange())
    return MentionText.containsMentions(selected)
      ? [.mactrixComposerText, .rtf, .html, .string] : super.writablePasteboardTypes
  }

  override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType)
    -> Bool
  {
    let selected = attributedString().attributedSubstring(from: selectedRange())
    if type == .mactrixComposerText || MentionText.containsMentions(selected) {
      return MentionText.writeSelection(selected, to: pasteboard, type: type)
    }
    return super.writeSelection(to: pasteboard, type: type)
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL,
      let uri = (try? MatrixUriScheme(parseUrl: url.absoluteString))
        ?? (try? MatrixUriScheme(parseMatrixToUrl: url.absoluteString))
    else { return false }

    return handleMatrixUri?(uri) ?? false
  }

  override func keyDown(with event: NSEvent) {
    if let direction = TimelineSelectionDirection(event: event), let onArrowKey {
      onArrowKey(direction)
    } else {
      super.keyDown(with: event)
    }
  }
}

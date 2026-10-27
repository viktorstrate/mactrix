import AppKit
import MactrixUI
import MessageFormatting

extension NSPasteboard.PasteboardType {
  static let mactrixComposerText = Self("org.mactrix.composer-text")
}

private enum ComposerClipboardSegment: Codable {
  case text(String)
  case mention(UserDragPayload)

  static func encode(segments: [ComposerClipboardSegment]) -> Data? {
    try? JSONEncoder().encode(segments)
  }

  static func decode(data: Data) -> [ComposerClipboardSegment]? {
    try? JSONDecoder().decode([ComposerClipboardSegment].self, from: data)
  }
}

final class ComposerMentionTextView: DynamicTextView {
  typealias AvatarURLLookup = @MainActor (String) async throws -> String?

  private let content = NSTextContentStorage()
  private var avatarURLs: [String: String] = [:]
  // Keep completed attempts too, so missing profiles and failures aren't retried on every edit.
  private var avatarLookups: [String: Task<Void, Never>] = [:]
  weak var imageLoader: ImageLoader?
  var avatarURLLookup: AvatarURLLookup?

  init() {
    let manager = NSTextLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    content.addTextLayoutManager(manager)
    manager.textContainer = container
    super.init(frame: .zero, textContainer: container)
    isRichText = true
    importsGraphics = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    for task in avatarLookups.values { task.cancel() }
  }

  var markdown: String { Self.markdown(from: attributedString()) }

  /// Loads draft text without registering user edits or emitting text-change notifications.
  func setMarkdown(_ markdown: String) {
    let attributes = typingAttributes.filter { $0.key != .attachment }
    let text = NSMutableAttributedString(string: markdown, attributes: attributes)
    for mention in parseMarkdownMentions(markdown).reversed() {
      let payload = UserDragPayload(userID: mention.userID, username: mention.username)
      let attachment = ComposerMentionAttachment(payload: payload, imageLoader: imageLoader)
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
  }

  func cancelAvatarLookups() {
    for task in avatarLookups.values { task.cancel() }
    avatarLookups.removeAll()
  }

  private func restoreMentionAvatars() {
    guard let avatarURLLookup else { return }
    let text = attributedString()
    var missingUserIDs: Set<String> = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      guard let mention = value as? ComposerMentionAttachment, mention.avatarUrl == nil else {
        return
      }
      if let avatarUrl = avatarURLs[mention.payload.userID] {
        mention.setAvatarUrl(avatarUrl)
      } else {
        missingUserIDs.insert(mention.payload.userID)
      }
    }
    for userID in missingUserIDs where avatarLookups[userID] == nil {
      avatarLookups[userID] = Task { [weak self] in
        guard let avatarUrl = try? await avatarURLLookup(userID),
          !Task.isCancelled, let self
        else { return }

        self.avatarURLs[userID] = avatarUrl
        self.restoreMentionAvatars()
      }
    }
  }

  static func markdown(from text: NSAttributedString) -> String {
    project(text, asMarkdown: true)
  }

  private static func project(_ text: NSAttributedString, asMarkdown: Bool) -> String {
    var result = ""
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      attachment, range, _ in
      if let mention = attachment as? ComposerMentionAttachment {
        result +=
          asMarkdown
          ? (mention.payload.markdownLink ?? mention.payload.userID) : mention.payload.userID
      } else {
        result += (text.string as NSString).substring(with: range)
      }
    }
    return result
  }

  override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    [.mactrixComposerText] + super.readablePasteboardTypes
  }

  override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType)
    -> Bool
  {
    guard isEditable else { return false }

    let segments: [ComposerClipboardSegment]
    switch type {
    case .mactrixComposerText:
      guard
        let data = pasteboard.data(forType: type),
        let decoded = ComposerClipboardSegment.decode(data: data)
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
            attachment: ComposerMentionAttachment(payload: payload, imageLoader: imageLoader),
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

    switch type {
    case .string:
      return pasteboard.setString(Self.project(selected, asMarkdown: false), forType: .string)
    case .mactrixComposerText:
      var segments: [ComposerClipboardSegment] = []
      selected.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selected.length)) {
        attachment, range, _ in
        if let mention = attachment as? ComposerMentionAttachment {
          segments.append(.mention(mention.pasteboardPayload))
        } else {
          segments.append(.text((selected.string as NSString).substring(with: range)))
        }
      }
      guard let data = ComposerClipboardSegment.encode(segments: segments) else { return false }
      return pasteboard.setData(data, forType: .mactrixComposerText)
    default:
      return false
    }
  }

  override func height(for width: CGFloat) -> CGFloat {
    // A separate TK2 layout preserves live wrapping during speculative size probes.
    let content = NSTextContentStorage()
    let manager = NSTextLayoutManager()
    content.addTextLayoutManager(manager)
    let container = NSTextContainer(
      size: NSSize(
        width: max(1, width - 2 * textContainerInset.width), height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 5
    manager.textContainer = container
    content.textStorage?.setAttributedString(attributedString())
    manager.ensureLayout(for: content.documentRange)
    var bottom: CGFloat = 0
    manager.enumerateTextLayoutFragments(
      from: content.documentRange.location, options: [.ensuresLayout, .ensuresExtraLineFragment]
    ) { fragment in
      bottom = max(bottom, fragment.layoutFragmentFrame.maxY)
      return true
    }
    let font = font ?? .systemFont(ofSize: 13)
    return ceil(
      max(bottom, font.ascender - font.descender + font.leading) + 2 * textContainerInset.height)
  }
}

final class ComposerMentionAttachment: NSTextAttachment {
  fileprivate static let avatarDidChangeNotification = Notification.Name(
    "ComposerMentionAttachment.avatarDidChange")

  let payload: UserDragPayload

  @MainActor private(set) var avatarUrl: String?
  @MainActor weak var imageLoader: ImageLoader?

  @MainActor var pasteboardPayload: UserDragPayload {
    UserDragPayload(userID: payload.userID, username: payload.username, avatarUrl: avatarUrl)
  }

  @MainActor func setAvatarUrl(_ avatarUrl: String) {
    guard self.avatarUrl != avatarUrl else { return }
    self.avatarUrl = avatarUrl
    NotificationCenter.default.post(name: Self.avatarDidChangeNotification, object: self)
  }

  @MainActor
  init(payload: UserDragPayload, imageLoader: ImageLoader? = nil) {
    self.payload = payload
    self.avatarUrl = payload.avatarUrl
    self.imageLoader = imageLoader
    super.init(data: nil, ofType: nil)
  }

  required init?(coder: NSCoder) { return nil }

  override var usesTextAttachmentView: Bool { true }

  override func viewProvider(
    for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
  ) -> NSTextAttachmentViewProvider? {
    ComposerMentionViewProvider(
      textAttachment: self, parentView: parentView,
      textLayoutManager: textContainer?.textLayoutManager, location: location)
  }

  /// Rasterize the view to an image
  override func image(
    for bounds: CGRect, attributes: [NSAttributedString.Key: Any] = [:],
    location: any NSTextLocation, textContainer: NSTextContainer?
  ) -> NSImage? {
    guard bounds.width > 0, bounds.height > 0,
      let provider = viewProvider(for: nil, location: location, textContainer: textContainer)
    else { return nil }

    nonisolated(unsafe) let uiProvider = provider
    return MainActor.assumeIsolated {
      uiProvider.loadView()
      guard let view = uiProvider.view else { return nil }
      view.setFrameSize(bounds.size)
      view.needsLayout = true
      view.layoutSubtreeIfNeeded()

      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let image = NSImage(size: bounds.size)
      image.addRepresentation(bitmap)
      return image
    }
  }

  override func attachmentBounds(
    for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
    textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint
  ) -> CGRect {
    _ = super.attachmentBounds(
      for: attributes, location: location, textContainer: textContainer,
      proposedLineFragment: proposedLineFragment, position: position)

    let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 13)
    let height = ceil(font.ascender - font.descender) + 6
    let labelWidth = (payload.username as NSString).size(withAttributes: [.font: font]).width
    let available = max(
      1,
      (textContainer?.size.width ?? proposedLineFragment.width) - 2
        * (textContainer?.lineFragmentPadding ?? 5))

    return CGRect(
      x: 0, y: font.descender - 3, width: min(available, ceil(labelWidth) + height + 12),
      height: height)
  }
}

private final class ComposerMentionViewProvider: NSTextAttachmentViewProvider {
  override func loadView() {
    guard let mention = textAttachment as? ComposerMentionAttachment else { return }
    // AppKit loads attachment views on the UI thread but its provider API is preconcurrency.
    nonisolated(unsafe) let uiAttachment = mention
    view = MainActor.assumeIsolated {
      ComposerMentionView(attachment: uiAttachment)
    }
  }
}

private final class ComposerMentionView: NSView {
  private let attachment: ComposerMentionAttachment
  private let avatar = AvatarView()
  private let label = NSTextField(labelWithString: "")

  init(attachment: ComposerMentionAttachment) {
    self.attachment = attachment
    super.init(frame: .zero)
    let payload = attachment.payload
    configureAvatar()
    label.stringValue = payload.username
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    addSubview(avatar)
    addSubview(label)
    setAccessibilityLabel(payload.username + " (" + payload.userID + ")")
    NotificationCenter.default.addObserver(
      self, selector: #selector(avatarChanged),
      name: ComposerMentionAttachment.avatarDidChangeNotification, object: attachment)
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionChanged),
      name: NSTextView.didChangeSelectionNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private func configureAvatar() {
    let payload = attachment.payload
    avatar.configure(
      userID: payload.userID, displayName: payload.username,
      avatarUrl: attachment.avatarUrl, kind: .user, imageLoader: attachment.imageLoader)
  }

  @objc private func avatarChanged(_ notification: Notification) {
    configureAvatar()
  }

  @objc private func selectionChanged(_ notification: Notification) {
    needsDisplay = true
  }

  private var editor: NSTextView? {
    var ancestor = superview
    while let view = ancestor {
      if let editor = view as? NSTextView { return editor }
      ancestor = view.superview
    }
    return nil
  }

  override func layout() {
    super.layout()
    let size = max(0, bounds.height - 4)
    avatar.frame = NSRect(x: 2, y: 2, width: size, height: size)
    label.font = editor?.font ?? .systemFont(ofSize: 13)
    label.frame = NSRect(
      x: size + 6, y: (bounds.height - label.intrinsicContentSize.height) / 2,
      width: max(0, bounds.width - size - 10), height: label.intrinsicContentSize.height)
  }

  func isSelected() -> Bool {
    var result = false
    if let editor {
      let text = editor.attributedString()
      text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
        value, range, _ in
        if value as? ComposerMentionAttachment === attachment {
          result = editor.selectedRanges.contains {
            NSIntersectionRange($0.rangeValue, range).length > 0
          }
        }
      }
    }
    return result
  }

  override func draw(_ dirtyRect: NSRect) {
    let selected = isSelected()
    let color = NSColor(userID: attachment.payload.userID)

    // color.withAlphaComponent(0.15).setFill()
    // label.textColor = selected ? .selectedTextColor : color

    (selected ? NSColor.selectedTextBackgroundColor : color.withAlphaComponent(0.15)).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    label.textColor = color
  }
}

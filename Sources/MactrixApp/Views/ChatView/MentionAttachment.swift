import AppKit
import MactrixUI

/// Hosts opt in explicitly so a temporarily disabled composer remains noninteractive.
@MainActor
protocol MentionAttachmentHost: NSTextView {
  var allowsMentionInteraction: Bool { get }
  func mentionInteractionBegan()
  func activateMention(_ attachment: MentionAttachment)
}

final class MentionAttachment: NSTextAttachment {
  fileprivate static let avatarDidChangeNotification = Notification.Name(
    "MentionAttachment.avatarDidChange")

  let payload: UserDragPayload
  /// Preserved for clipboard export, independently of the host's activation behavior.
  let navigationURL: URL?

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
  init(payload: UserDragPayload, imageLoader: ImageLoader? = nil, navigationURL: URL? = nil) {
    self.payload = payload
    self.navigationURL = navigationURL ?? payload.url.flatMap(URL.init(string:))
    self.avatarUrl = payload.avatarUrl
    self.imageLoader = imageLoader
    super.init(data: nil, ofType: nil)
  }

  required init?(coder: NSCoder) { return nil }

  override var usesTextAttachmentView: Bool { true }

  override func viewProvider(
    for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
  ) -> NSTextAttachmentViewProvider? {
    MentionViewProvider(
      textAttachment: self, parentView: parentView,
      textLayoutManager: textContainer?.textLayoutManager, location: location)
  }

  override func image(
    for bounds: CGRect, attributes: [NSAttributedString.Key: Any] = [:],
    location: any NSTextLocation, textContainer: NSTextContainer?
  ) -> NSImage? {
    guard bounds.width > 0, bounds.height > 0,
      let provider = viewProvider(for: nil, location: location, textContainer: textContainer)
    else { return nil }

    nonisolated(unsafe) let uiProvider = provider
    nonisolated(unsafe) let font = attributes[.font] as? NSFont
    return MainActor.assumeIsolated {
      uiProvider.loadView()
      guard let view = uiProvider.view else { return nil }
      if let pill = view as? MentionView { pill.fallbackFont = font }
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

private final class MentionViewProvider: NSTextAttachmentViewProvider {
  override func loadView() {
    guard let mention = textAttachment as? MentionAttachment else { return }
    // AppKit loads attachment views on the UI thread but its provider API is preconcurrency.
    nonisolated(unsafe) let uiAttachment = mention
    view = MainActor.assumeIsolated {
      MentionView(attachment: uiAttachment)
    }
  }
}

private final class MentionButtonCell: NSButtonCell {
  override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
    super.highlight(flag, withFrame: cellFrame, in: controlView)
    controlView.alphaValue = flag ? 0.6 : 1
  }
}

private final class MentionView: NSButton {
  private let attachment: MentionAttachment
  private let avatar = AvatarView()
  private let label = NSTextField(labelWithString: "")
  var fallbackFont: NSFont?

  init(attachment: MentionAttachment) {
    self.attachment = attachment
    super.init(frame: .zero)
    cell = MentionButtonCell(textCell: "")
    setButtonType(.momentaryChange)
    isBordered = false
    title = ""
    target = self
    action = #selector(activate)
    let payload = attachment.payload
    configureAvatar()
    label.stringValue = payload.username
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    addSubview(avatar)
    addSubview(label)
    setAccessibilityLabel(payload.username + " (" + payload.userID + ")")
    setAccessibilityChildren([])
    NotificationCenter.default.addObserver(
      self, selector: #selector(avatarChanged),
      name: MentionAttachment.avatarDidChangeNotification, object: attachment)
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionChanged),
      name: NSTextView.didChangeSelectionNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private var interactionHost: (any MentionAttachmentHost)? {
    guard let editor, !editor.isEditable,
      let host = editor as? any MentionAttachmentHost, host.allowsMentionInteraction
    else { return nil }
    return host
  }

  override var acceptsFirstResponder: Bool {
    interactionHost != nil && super.acceptsFirstResponder
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard interactionHost != nil, super.hitTest(point) != nil else { return nil }
    return self
  }

  override func resetCursorRects() {
    if interactionHost != nil { addCursorRect(bounds, cursor: .pointingHand) }
  }

  override func mouseDown(with event: NSEvent) {
    guard let host = interactionHost else { return }
    if event.modifierFlags.contains(.control) {
      editor?.rightMouseDown(with: event)
      return
    }
    host.mentionInteractionBegan()
    defer { cell?.highlight(false, withFrame: bounds, in: self) }
    super.mouseDown(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    editor?.rightMouseDown(with: event)
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { cell?.highlight(false, withFrame: bounds, in: self) }
    super.viewWillMove(toWindow: newWindow)
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    interactionHost == nil ? .staticText : .button
  }

  override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
    if selector == #selector(accessibilityPerformPress), interactionHost == nil { return false }
    return super.isAccessibilitySelectorAllowed(selector)
  }

  override func accessibilityPerformPress() -> Bool {
    guard let host = interactionHost else { return false }
    host.mentionInteractionBegan()
    host.activateMention(attachment)
    return true
  }

  @objc private func activate() {
    interactionHost?.activateMention(attachment)
  }

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
    guard notification.object as? NSTextView === editor else { return }
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

  private func attachmentRange(in text: NSAttributedString) -> NSRange? {
    var result: NSRange?
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, range, stop in
      if value as? MentionAttachment === attachment {
        result = range
        stop.pointee = true
      }
    }
    return result
  }

  override func layout() {
    super.layout()
    let size = max(0, bounds.height - 4)
    avatar.frame = NSRect(x: 2, y: 2, width: size, height: size)
    let text = editor?.attributedString()
    let range = text.flatMap { attachmentRange(in: $0) }
    let font = range.flatMap {
      text?.attribute(.font, at: $0.location, effectiveRange: nil) as? NSFont
    }
    label.font = font ?? fallbackFont ?? editor?.font ?? .systemFont(ofSize: 13)
    label.frame = NSRect(
      x: size + 6, y: (bounds.height - label.intrinsicContentSize.height) / 2,
      width: max(0, bounds.width - size - 10), height: label.intrinsicContentSize.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    let color = NSColor(userID: attachment.payload.userID)
    color.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    label.textColor = color
  }
}

import AppKit
import MactrixUI
import MatrixProtocols
import MatrixRustSDK
import MessageFormatting
import Observation

final class ComposerMentionTextView: DynamicTextView {
  typealias AvatarURLLookup = MentionAvatarLoader.AvatarURLLookup

  let mentionAutocomplete = ComposerMentionAutocompleteSession<MatrixRustSDK.RoomMember>()
  var mentionCandidateProvider: (() -> [MatrixRustSDK.RoomMember])?
  private(set) var mentionAutocompleteWindow: ComposerMentionAutocompleteWindow?

  private let mentionGeometryViews = NSHashTable<NSView>.weakObjects()
  private weak var mentionObservedWindow: NSWindow?
  private var isUpdatingMentionPresentation = false
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
    NotificationCenter.default.addObserver(
      self, selector: #selector(mentionFocusDidEnd),
      name: NSApplication.didResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(synchronizeMentionAutocompleteWindow),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    observeMentionAutocomplete()
  }

  isolated deinit {
    closeMentionAutocompleteWindow()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var textContent: ComposerTextContent { Self.textContent(from: attributedString()) }

  var markdown: String { textContent.markdown }

  /// Loads draft text without registering user edits or emitting text-change notifications.
  func setMarkdown(_ markdown: String) {
    endMentionAutocomplete()
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

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
    if !hasMarkedText(), modifiers == [.command],
      event.specialKey == .enter || event.specialKey == .carriageReturn
    {
      endMentionAutocomplete()
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
    guard isEditable, !hasMarkedText(), modifiers.isEmpty else {
      super.keyDown(with: event)
      return
    }

    // U+001B is ASCII ESC, produced by the Escape key.
    if event.charactersIgnoringModifiers == "\u{1b}", mentionAutocomplete.query != nil {
      mentionAutocomplete.dismiss()
      closeMentionAutocompleteWindow()
      return
    }

    switch event.specialKey {
    case .upArrow, .downArrow:
      let suggestions = mentionAutocomplete.suggestions
      if !suggestions.isEmpty, validatedMentionReplacementRange() != nil {
        let current =
          suggestions.firstIndex {
            $0.userId == mentionAutocomplete.highlightedUserID
          } ?? 0
        let offset = event.specialKey == .downArrow ? 1 : -1
        let next = min(max(current + offset, 0), suggestions.count - 1)
        mentionAutocomplete.highlight(userID: suggestions[next].userId)
        return
      }
    case .enter, .carriageReturn:
      if mentionAutocomplete.query != nil, !mentionAutocomplete.suggestions.isEmpty {
        acceptHighlightedMention()
        return
      }
      endMentionAutocomplete()

    default:
      break
    }
    super.keyDown(with: event)
  }

  @discardableResult
  func acceptHighlightedMention() -> Bool {
    guard let profile = mentionAutocomplete.highlightedSuggestion,
      var range = validatedMentionReplacementRange()
    else {
      endMentionAutocomplete()
      return false
    }
    let attributes = typingAttributes.filter { $0.key != .attachment }
    let payload = UserDragPayload(
      userId: profile.userId,
      username: profile.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? profile.userId,
      avatarUrl: profile.avatarUrl)
    let replacement = NSMutableAttributedString(
      attachment: MentionAttachment(payload: payload, imageLoader: imageLoader),
      attributes: attributes)
    replacement.append(NSAttributedString(string: " ", attributes: attributes))
    // Reuse an existing separator so accepting in the middle of a sentence does not double it.
    if (string as NSString).substring(from: NSMaxRange(range)).hasPrefix(" ") {
      range.length += 1
    }
    breakUndoCoalescing()
    insertText(replacement, replacementRange: range)
    breakUndoCoalescing()
    typingAttributes = attributes
    endMentionAutocomplete()
    return true
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

  private func observeMentionAutocomplete() {
    withObservationTracking {
      _ = mentionAutocomplete.query
      _ = mentionAutocomplete.suggestions
      _ = mentionAutocomplete.highlightedUserID
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observeMentionAutocomplete()
      }
    }
    synchronizeMentionAutocompleteWindow()
  }

  @objc private func synchronizeMentionAutocompleteWindow() {
    guard mentionInputChangeDepth == 0, !isUpdatingMentionPresentation else { return }
    isUpdatingMentionPresentation = true
    defer { isUpdatingMentionPresentation = false }
    guard !mentionAutocomplete.suggestions.isEmpty, let parent = window,
      let anchor = mentionAnchorRect(),
      let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY))
      }) ?? parent.screen
    else {
      closeMentionAutocompleteWindow()
      return
    }

    let popup = mentionAutocompleteWindow ?? ComposerMentionAutocompleteWindow()
    mentionAutocompleteWindow = popup
    popup.imageLoader = self.imageLoader
    popup.onHighlight = { [weak self] userID in
      self?.mentionAutocomplete.highlight(userID: userID)
    }
    popup.onSubmit = { [weak self] in
      self?.acceptHighlightedMention()
    }
    popup.update(
      suggestions: mentionAutocomplete.suggestions,
      highlightedUserID: mentionAutocomplete.highlightedUserID)
    let frame = ComposerMentionAutocompleteWindow.frame(
      anchoredTo: anchor, preferredSize: popup.preferredSize, visibleFrame: screen.visibleFrame)
    if popup.frame != frame { popup.setFrame(frame, display: true) }
    if popup.parent !== parent { parent.addChildWindow(popup, ordered: .above) }
    if !popup.isVisible { popup.orderFront(nil) }
  }

  private func mentionAnchorRect() -> NSRect? {
    guard isEditable, !isHiddenOrHasHiddenAncestor, let window, window.isKeyWindow,
      window.firstResponder === self, let range = validatedMentionReplacementRange()
    else { return nil }
    // NSTextInputClient returns screen coordinates and supports the live TextKit 2 layout.
    let anchor = firstRect(
      forCharacterRange: NSRange(location: range.location, length: 1), actualRange: nil)
    let visible = window.convertToScreen(convert(visibleRect, to: nil))
    guard anchor.height > 0, anchor.intersects(visible) else { return nil }
    return anchor
  }

  func endMentionAutocomplete() {
    mentionAutocomplete.reset()
    closeMentionAutocompleteWindow()
  }

  private func closeMentionAutocompleteWindow() {
    guard let popup = mentionAutocompleteWindow else { return }
    popup.parent?.removeChildWindow(popup)
    popup.orderOut(nil)
    popup.close()
    mentionAutocompleteWindow = nil
  }

  @objc private func mentionFocusDidEnd() {
    endMentionAutocomplete()
  }

  private func observeMentionGeometry() {
    let center = NotificationCenter.default
    for view in mentionGeometryViews.allObjects {
      center.removeObserver(self, name: NSView.frameDidChangeNotification, object: view)
      center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: view)
    }
    mentionGeometryViews.removeAllObjects()
    if let oldWindow = mentionObservedWindow {
      for name in Self.mentionWindowGeometryNotifications + Self.mentionWindowDismissNotifications {
        center.removeObserver(self, name: name, object: oldWindow)
      }
    }
    mentionObservedWindow = window
    guard let window else { return }
    var ancestor: NSView? = self
    while let view = ancestor {
      mentionGeometryViews.add(view)
      view.postsFrameChangedNotifications = true
      view.postsBoundsChangedNotifications = true
      for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
        center.addObserver(
          self, selector: #selector(synchronizeMentionAutocompleteWindow), name: name, object: view)
      }
      ancestor = view.superview
    }
    for name in Self.mentionWindowGeometryNotifications {
      center.addObserver(
        self, selector: #selector(synchronizeMentionAutocompleteWindow), name: name, object: window)
    }
    for name in Self.mentionWindowDismissNotifications {
      center.addObserver(
        self, selector: #selector(mentionFocusDidEnd), name: name, object: window)
    }
  }

  private static let mentionWindowGeometryNotifications = [
    NSWindow.didMoveNotification, NSWindow.didResizeNotification,
    NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
  ]
  private static let mentionWindowDismissNotifications = [
    NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
  ]

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if window !== newWindow { endMentionAutocomplete() }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    observeMentionGeometry()
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    observeMentionGeometry()
  }

  override func layout() {
    super.layout()
    synchronizeMentionAutocompleteWindow()
  }

  override func becomeFirstResponder() -> Bool {
    let becameResponder = super.becomeFirstResponder()
    if becameResponder { updateMentionAutocomplete() }
    return becameResponder
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { endMentionAutocomplete() }
    return resigned
  }

  override func viewDidHide() {
    super.viewDidHide()
    endMentionAutocomplete()
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

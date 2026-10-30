import AppKit
import MatrixIntegration
import MatrixRustSDK
import MessageFormatting
import Observation

final class MessageEditingView: NSView, NSTextViewDelegate {
  private let editor = ComposerMentionTextView()

  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
  private let editErrorLabel = NSTextField(labelWithString: "")
  private var editState: MessageEditState?
  private var restoringEditor = false
  private var mentionObservationGeneration = 0

  public var isEditing: Bool { editState != nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    editor.onSubmit = { [weak self] in self?.saveEdit() }

    updateFonts()
    editor.isHorizontallyResizable = false
    editor.isVerticallyResizable = true
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainerInset = NSSize(width: 2, height: 5)
    editor.delegate = self
    editor.setAccessibilityLabel("Edit message")

    editor.wantsLayer = true
    editor.layer?.borderWidth = 1
    editor.layer?.borderColor = NSColor.separatorColor.cgColor
    editor.layer?.cornerRadius = 6
    editor.layer?.masksToBounds = true

    saveButton.target = self
    saveButton.action = #selector(saveEdit)
    saveButton.keyEquivalent = "\r"
    saveButton.keyEquivalentModifierMask = [.command]

    cancelButton.target = self
    cancelButton.action = #selector(cancelEdit)
    cancelButton.keyEquivalent = "\u{1b}"  // escape button
    cancelButton.keyEquivalentModifierMask = []

    editErrorLabel.textColor = .systemRed
    editErrorLabel.lineBreakMode = .byTruncatingTail
    editErrorLabel.isSelectable = true

    for view in [editor, saveButton, cancelButton, editErrorLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }

    NSLayoutConstraint.activate([
      editor.leadingAnchor.constraint(equalTo: leadingAnchor),
      editor.trailingAnchor.constraint(equalTo: trailingAnchor),
      editor.topAnchor.constraint(equalTo: topAnchor),
      editor.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -6),

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

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    effectiveAppearance.performAsCurrentDrawingAppearance {
      editor.layer?.borderColor = NSColor.separatorColor.cgColor
    }
  }

  private func updateFonts() {
    let editorFont = NSFont.systemFont(ofSize: TimelineTypography.scaled(13))
    if editor.font != editorFont {
      editor.font = editorFont
      editor.invalidateIntrinsicContentSize()
    }
    let controlFont = NSFont.systemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
    saveButton.font = controlFont
    cancelButton.font = controlFont
    editErrorLabel.font = controlFont
  }

  func height(for width: CGFloat) -> CGFloat {
    updateFonts()
    let controlsHeight = max(
      saveButton.intrinsicContentSize.height,
      cancelButton.intrinsicContentSize.height,
      editErrorLabel.intrinsicContentSize.height)
    return editor.height(for: width) + 6 + controlsHeight
  }

  func configureEditing(_ state: MessageEditState?) {
    updateFonts()
    let stateChanged = editState !== state
    if stateChanged {
      mentionObservationGeneration += 1
      editor.endMentionAutocomplete()
      editor.cancelAvatarLookups()
    }
    editState = state
    editor.mentionCandidateProvider = state?.mentionCandidateProvider
    editor.imageLoader = state?.imageLoader
    guard let state else {
      editor.isEditable = false
      return
    }

    if stateChanged || editor.markdown != state.text {
      restoringEditor = true
      editor.setMarkdown(state.text)
      restoringEditor = false
    }

    editor.isEditable = !state.isSaving
    if state.isSaving { editor.endMentionAutocomplete() }
    if stateChanged {
      observeMentionCandidates(for: state, generation: mentionObservationGeneration)
    }
    if editor.mentionAutocomplete.query != nil { editor.updateMentionAutocomplete() }
    saveButton.isEnabled = !state.isSaving
    cancelButton.isEnabled = !state.isSaving
    saveButton.title = state.isSaving ? "Saving…" : "Save"
    editErrorLabel.stringValue = state.error ?? ""
    editErrorLabel.toolTip = state.error
  }

  private func observeMentionCandidates(for state: MessageEditState, generation: Int) {
    withObservationTracking {
      _ = state.mentionCandidateProvider?()
    } onChange: { [weak self, weak state] in
      Task { @MainActor [weak self, weak state] in
        guard let self, let state, editState === state,
          mentionObservationGeneration == generation
        else { return }
        observeMentionCandidates(for: state, generation: generation)
        if editor.mentionAutocomplete.query != nil { editor.updateMentionAutocomplete() }
      }
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === editor else { return super.performKeyEquivalent(with: event) }
    let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
    let isEscape = modifiers.isEmpty && event.charactersIgnoringModifiers == "\u{1b}"
    let isSave =
      modifiers == [.command]
      && (event.specialKey == .enter || event.specialKey == .carriageReturn)
    if editor.hasMarkedText(), isEscape || isSave { return false }
    // Button shortcuts are checked before keyDown; let autocomplete consume Escape first.
    if isEscape, editor.mentionAutocomplete.query != nil {
      editor.keyDown(with: event)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  func textDidChange(_ notification: Notification) {
    guard !restoringEditor, let state = editState else { return }
    state.text = editor.markdown
    state.onChange?()
  }

  @objc private func saveEdit() {
    guard let state = editState, !state.isSaving else { return }
    editor.endMentionAutocomplete()
    state.text = editor.markdown
    state.onSave?()
  }

  @objc private func cancelEdit() {
    guard let state = editState, !state.isSaving else { return }
    editor.endMentionAutocomplete()
    state.onCancel?()
  }
}

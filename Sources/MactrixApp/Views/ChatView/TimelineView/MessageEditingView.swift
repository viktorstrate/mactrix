import AppKit
import MatrixIntegration
import MatrixRustSDK
import MessageFormatting

final class MessageEditingView: NSView, NSTextViewDelegate {
  private let editor = DynamicTextView(frame: .zero)

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

  func height(for width: CGFloat) -> CGFloat {
    editor.height(for: width) + 6 + saveButton.intrinsicContentSize.height
  }

  func configureEditing(_ state: MessageEditState?) {
    editState = state
    guard let state else { return }

    if editor.string != state.text {
      restoringEditor = true
      editor.string = state.text
      editor.invalidateIntrinsicContentSize()
      restoringEditor = false
    }

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
    state.onChange?()
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

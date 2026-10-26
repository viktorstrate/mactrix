import AppKit

/// The controller's editor synchronization and deferred-focus lifetime.
@MainActor
final class ComposerEditorSession {
  let editor: DynamicTextView
  let composer: ChatComposerState
  private(set) var fulfilledFocus = 0
  private var requestedFocus = 0
  private var focusTask: Task<Void, Never>?

  init(editor: DynamicTextView, composer: ChatComposerState) {
    self.editor = editor
    self.composer = composer
  }

  func synchronize(text: String, enabled: Bool, placeholder: String, fontSize: Int) {
    if editor.string != text {
      editor.string = text
      editor.invalidateIntrinsicContentSize()
    }
    let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
    if editor.font != font { editor.font = font }
    editor.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
    editor.needsDisplay = true
    editor.isEditable = enabled
    editor.isSelectable = enabled
    editor.alphaValue = enabled ? 1 : 0.5
    if !enabled, editor.window?.firstResponder === editor {
      editor.window?.makeFirstResponder(nil)
    }
    requestFocus(requestedFocus)
  }

  func textDidChange() {
    guard editor.isEditable else { return }
    if composer.text != editor.string { composer.text = editor.string }
  }

  func requestFocus(_ request: Int) {
    requestedFocus = request
    guard editor.isEditable, request != fulfilledFocus else { return }
    focusTask?.cancel()
    focusTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled, let self, editor.isEditable,
        requestedFocus == request, let window = editor.window
      else { return }
      if window.makeFirstResponder(editor) { fulfilledFocus = request }
    }
  }

  func tearDown() {
    focusTask?.cancel()
    focusTask = nil
  }
}

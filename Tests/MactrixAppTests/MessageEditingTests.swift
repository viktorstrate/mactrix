import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

@MainActor
struct MessageEditingTests {
  @Test func draftSurvivesViewReconstruction() throws {
    let state = MessageEditState(
      id: MatrixRustSDK.EventOrTransactionId.eventId(eventId: "event"), text: "Original")
    let first = MessageTextContentView()
    first.configureEditing(state)
    let editor = try #require(findEditor(in: first))
    editor.string = "Updated draft"
    editor.setSelectedRange(NSRange(location: 3, length: 2))
    first.cachedEditingView?.textDidChange(
      Notification(name: NSText.didChangeNotification, object: editor))
    first.configureEditing(nil)

    let reconstructed = MessageTextContentView()
    reconstructed.configureEditing(state)
    let restored = try #require(findEditor(in: reconstructed))
    #expect(restored.string == "Updated draft")
    let editingView = try #require(reconstructed.cachedEditingView)
    #expect(
      reconstructed.height(forCaption: nil, formatted: nil, width: 200)
        == editingView.height(for: 200))
    reconstructed.configureEditing(nil)
    #expect(!reconstructed.isEditing)
  }

  @Test func emptyMediaCaptionGetsEditorHeight() throws {
    let source = try MediaSource.fromUrl(url: "mxc://example.org/file")
    let file = FileMessageContent(
      filename: "file.pdf", caption: nil, formattedCaption: nil, source: source, info: nil)
    let state = MessageEditState(
      id: MatrixRustSDK.EventOrTransactionId.eventId(eventId: "event"), text: "")
    let view = MessageFileContentView()
    let originalHeight = view.height(for: file, width: 240)
    view.configureEditing(state)
    let captionView = MessageTextContentView()
    captionView.configureEditing(state)
    let editorHeight = captionView.height(forCaption: nil, formatted: nil, width: 240)
    #expect(editorHeight > 0)
    #expect(view.height(for: file, width: 240) == originalHeight + 10 + ceil(editorHeight))
    view.configureEditing(nil)
    #expect(view.height(for: file, width: 240) == originalHeight)

    let gallery = GalleryMessageContent(body: "", formatted: nil, itemtypes: [])
    let galleryView = MessageGalleryContentView()
    galleryView.configureEditing(state)
    galleryView.configure(gallery: gallery, matrixClient: nil)
    #expect(galleryView.height(for: gallery, width: 240) == ceil(editorHeight))
    galleryView.configureEditing(nil)
    #expect(galleryView.height(for: gallery, width: 240) == 0)
  }

  @Test func editorHeightTracksContentAndWidth() {
    let state = MessageEditState(
      id: MatrixRustSDK.EventOrTransactionId.eventId(eventId: "event"), text: "")
    let view = MessageTextContentView()
    view.configureEditing(state)
    let emptyHeight = view.height(forCaption: nil, formatted: nil, width: 240)
    #expect(emptyHeight > 0)

    state.text = "First line\nSecond line\n"
    view.configureEditing(state)
    let multilineHeight = view.height(forCaption: nil, formatted: nil, width: 240)
    #expect(multilineHeight > emptyHeight)

    state.text = String(repeating: "A message with wrapping text. ", count: 10)
    view.configureEditing(state)
    let wideHeight = view.height(forCaption: nil, formatted: nil, width: 400)
    let narrowHeight = view.height(forCaption: nil, formatted: nil, width: 120)
    #expect(narrowHeight > wideHeight)
    #expect(view.height(forCaption: nil, formatted: nil, width: 400) == wideHeight)
  }

  @Test func measuringProposedWidthPreservesEditorLayout() throws {
    let editor = DynamicTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.textContainerInset = DynamicTextView.padding
    editor.font = .systemFont(ofSize: 13)
    let container = try #require(unsafe editor.textContainer)
    let manager = try #require(unsafe editor.layoutManager)
    container.widthTracksTextView = true
    editor.string = String(repeating: "A message with wrapping text. ", count: 10)
    manager.ensureLayout(for: container)
    let originalSize = container.containerSize
    let originalUsedRect = manager.usedRect(for: container)
    let originalFrame = editor.frame

    let wideHeight = editor.height(for: 600)
    let narrowHeight = editor.height(for: 120)

    #expect(narrowHeight > wideHeight)
    #expect(container.containerSize == originalSize)
    #expect(manager.usedRect(for: container) == originalUsedRect)
    #expect(editor.frame == originalFrame)
    #expect(editor.height(for: 600) == wideHeight)
  }

  private func findEditor(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.isEditable { return text }
    for child in view.subviews {
      if let editor = findEditor(in: child) { return editor }
    }
    return nil
  }
}

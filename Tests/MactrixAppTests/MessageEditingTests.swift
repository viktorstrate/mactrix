import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

@MainActor
struct MessageEditingTests {
  @Test func draftAndSelectionSurviveViewReconstruction() throws {
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
    #expect(restored.selectedRange() == NSRange(location: 3, length: 2))
    #expect(reconstructed.height(forCaption: nil, formatted: nil, width: 200) == 140)
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
    #expect(view.height(for: file, width: 240) >= originalHeight + 140)
    view.configureEditing(nil)
    #expect(view.height(for: file, width: 240) == originalHeight)

    let gallery = GalleryMessageContent(body: "", formatted: nil, itemtypes: [])
    let galleryView = MessageGalleryContentView()
    galleryView.configureEditing(state)
    galleryView.configure(gallery: gallery, matrixClient: nil)
    #expect(galleryView.height(for: gallery, width: 240) == 140)
    galleryView.configureEditing(nil)
    #expect(galleryView.height(for: gallery, width: 240) == 0)
  }

  private func findEditor(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.isEditable { return text }
    for child in view.subviews {
      if let editor = findEditor(in: child) { return editor }
    }
    return nil
  }
}

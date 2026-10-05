import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

@MainActor
struct MessageGalleryContentViewTests {
  @Test func mixedGalleryMeasuresExistingRenderersAndFinalCaption() throws {
    let source = try MediaSource.fromUrl(url: "mxc://example.org/attachment")
    let image = ImageMessageContent(
      filename: "image.png", caption: "Image caption", formattedCaption: nil,
      source: source, info: nil)
    let video = VideoMessageContent(
      filename: "video.mp4", caption: "Video caption", formattedCaption: nil,
      source: source, info: nil)
    let file = FileMessageContent(
      filename: "file.pdf", caption: "File caption", formattedCaption: nil,
      source: source, info: nil)
    let gallery = GalleryMessageContent(
      body: "Final gallery caption", formatted: nil,
      itemtypes: [.image(content: image), .video(content: video), .file(content: file)])
    let width: CGFloat = 240
    let expected =
      ceil(MessageImageContentView().height(for: image, width: width))
      + ceil(MessageVideoContentView().height(for: video, width: width))
      + ceil(MessageFileContentView().height(for: file, width: width))
      + 32 + 10
      + ceil(
        MessageTextContentView().height(
          forCaption: gallery.body, formatted: nil, width: width))
    let view = MessageGalleryContentView()
    #expect(view.height(for: gallery, width: width) == expected)
    // Measuring requires no client and does not create displayed attachments.
    #expect(view.subviews.count == 1)

    view.frame = NSRect(x: 0, y: 0, width: width, height: expected)
    view.configure(gallery: gallery, matrixClient: nil)
    view.layoutSubtreeIfNeeded()
    let media = view.subviews.filter { !($0 is MessageTextContentView) }
    #expect(media.count == 3)
    #expect(media[0] is MessageImageContentView)
    #expect(media[1] is MessageVideoContentView)
    #expect(media[2] is MessageFileContentView)
    #expect(abs(media[0].frame.minY - media[1].frame.maxY - 16) < 1)
    #expect(abs(media[1].frame.minY - media[2].frame.maxY - 16) < 1)
    let finalCaption = try #require(view.subviews.first { $0 is MessageTextContentView })
    #expect(abs(media[2].frame.minY - finalCaption.frame.maxY - 10) < 1)
    #expect(abs(finalCaption.frame.minY) < 1)
    #expect(
      abs(
        media[0].frame.height
          - ceil(
            MessageImageContentView().height(
              for: image, width: width))) < 1)
  }

  @Test func absentCaptionsAndEmptyGalleriesHaveNoExtraSpacing() throws {
    let source = try MediaSource.fromUrl(url: "mxc://example.org/file")
    let file = FileMessageContent(
      filename: "file.pdf", caption: nil, formattedCaption: nil, source: source, info: nil)
    let view = MessageGalleryContentView()
    #expect(
      view.height(
        for: GalleryMessageContent(body: "", formatted: nil, itemtypes: []), width: 200) == 0)
    #expect(
      view.height(
        for: GalleryMessageContent(body: "", formatted: nil, itemtypes: [.file(content: file)]),
        width: 200) == 36)
    #expect(
      view.height(
        for: GalleryMessageContent(
          body: "", formatted: nil, itemtypes: [.file(content: file), .file(content: file)]),
        width: 200) == 88)
  }

  @Test func reuseRemovesOldChildrenAndKeepsCompatibleViews() throws {
    let source = try MediaSource.fromUrl(url: "mxc://example.org/file")
    let file = FileMessageContent(
      filename: "file.pdf", caption: "Caption", formattedCaption: nil, source: source, info: nil)
    let view = MessageGalleryContentView()
    view.configure(
      gallery: GalleryMessageContent(
        body: "Gallery caption", formatted: nil,
        itemtypes: [.file(content: file), .other(itemtype: "custom", body: "Unknown")]),
      matrixClient: nil)
    let original = try #require(view.subviews.first { $0 is MessageFileContentView })
    view.configure(
      gallery: GalleryMessageContent(body: "", formatted: nil, itemtypes: [.file(content: file)]),
      matrixClient: nil)
    #expect(view.subviews.count == 2)
    #expect(view.subviews.contains { $0 === original })
    #expect(view.subviews.compactMap { $0 as? MessageTextContentView }.allSatisfy { $0.isHidden })
    view.configure(
      gallery: GalleryMessageContent(body: "", formatted: nil, itemtypes: []), matrixClient: nil)
    #expect(view.subviews.count == 1)
  }

  @Test func audioFallbackPreservesCaptionAndUnsupportedItemsRemainVisible() throws {
    let audio = AudioMessageContent(
      filename: "audio.ogg", caption: "Audio caption", formattedCaption: nil,
      source: try MediaSource.fromUrl(url: "mxc://example.org/audio"), info: nil,
      audio: nil, voice: nil)
    let attachment = MessageAttachmentContent(item: .audio(content: audio))
    #expect(attachment.view is MessageFileContentView)
    #expect(attachment.height(for: .audio(content: audio), width: 200) > 36)
    let unknown = GalleryItemType.other(itemtype: "custom", body: "Unknown attachment")
    #expect(MessageAttachmentContent(item: unknown).height(for: unknown, width: 200) > 0)
  }

  @Test func captionsReflowWhenWidthChanges() {
    let gallery = GalleryMessageContent(
      body: String(repeating: "A long gallery caption. ", count: 10), formatted: nil,
      itemtypes: [])
    let view = MessageGalleryContentView()
    #expect(view.height(for: gallery, width: 100) > view.height(for: gallery, width: 400))
  }
}

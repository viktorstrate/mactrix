import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

@MainActor
struct TimelineTypographyTests {
  @Test func preferenceScalesReusedViewsAndMeasurements() throws {
    let defaults = UserDefaults.standard
    let original = defaults.object(forKey: "fontSize")
    defer {
      if let original {
        defaults.set(original, forKey: "fontSize")
      } else {
        defaults.removeObject(forKey: "fontSize")
      }
    }

    defaults.removeObject(forKey: "fontSize")
    #expect(TimelineTypography.fontSize == 13)
    #expect(TimelineTypography.scaled(10) == 10)

    let reply = MessageReplyPreviewView()
    reply.configure(details: .pending)
    let smallReplyHeight = MessageReplyPreviewView.height(for: .pending, width: 240)
    let caption = MessageTextContentView()
    let text = String(repeating: "Wrapping timeline content. ", count: 8)
    let smallCaptionHeight = caption.height(forCaption: text, formatted: nil, width: 240)
    let smallProfileHeight = MessageProfileRowView.rowHeight
    let smallTypingHeight = TypingIndicatorRowView.rowHeight
    let smallReceiptHeight = MessageReadReceiptsView.rowHeight
    let typing = TypingIndicatorRowView()
    typing.configure(names: ["Alice"])
    let editing = MessageTextContentView()
    let state = MessageEditState(id: .eventId(eventId: "event"), text: text)
    editing.configureEditing(state)
    let smallEditorHeight = editing.height(forCaption: nil, formatted: nil, width: 240)

    defaults.set(26, forKey: "fontSize")
    #expect(TimelineTypography.scaled(10) == 20)
    reply.configure(details: .pending)
    let replyLabel = try #require(reply.subviews.compactMap { $0 as? NSTextField }.first)
    #expect(replyLabel.font?.pointSize == 26)
    #expect(MessageReplyPreviewView.height(for: .pending, width: 240) > smallReplyHeight)
    caption.configureCaption(text, formatted: nil)
    #expect(caption.height(forCaption: text, formatted: nil, width: 240) > smallCaptionHeight)
    #expect(MessageProfileRowView.rowHeight > smallProfileHeight)
    #expect(TypingIndicatorRowView.rowHeight > smallTypingHeight)
    #expect(MessageReadReceiptsView.rowHeight > smallReceiptHeight)
    typing.configure(names: ["Alice"])
    let typingLabel = try #require(textFields(in: typing).first)
    let typingFont = try #require(
      typingLabel.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(typingFont.pointSize == TimelineTypography.scaled(NSFont.systemFontSize))
    editing.configureEditing(state)
    #expect(editing.height(forCaption: nil, formatted: nil, width: 240) > smallEditorHeight)
    #expect(state.text == text)

    defaults.set(13, forKey: "fontSize")
    reply.configure(details: .pending)
    #expect(replyLabel.font?.pointSize == 13)
    #expect(MessageReplyPreviewView.height(for: .pending, width: 240) == smallReplyHeight)
    #expect(caption.height(forCaption: text, formatted: nil, width: 240) == smallCaptionHeight)
    editing.configureEditing(state)
    #expect(editing.height(forCaption: nil, formatted: nil, width: 240) == smallEditorHeight)
  }

  @Test func avatarsAndFileIconsScaleButMediaDimensionsStayFixed() throws {
    let defaults = UserDefaults.standard
    let original = defaults.object(forKey: "fontSize")
    defer {
      if let original {
        defaults.set(original, forKey: "fontSize")
      } else {
        defaults.removeObject(forKey: "fontSize")
      }
    }

    defaults.set(13, forKey: "fontSize")
    let source = try MediaSource.fromUrl(url: "mxc://example.org/attachment")
    let file = FileMessageContent(
      filename: "file.pdf", caption: nil, formattedCaption: nil, source: source, info: nil)
    let image = ImageMessageContent(
      filename: "image.png", caption: nil, formattedCaption: nil, source: source, info: nil)
    let video = VideoMessageContent(
      filename: "video.mp4", caption: nil, formattedCaption: nil, source: source, info: nil)
    let imageView = MessageImageContentView()
    let videoView = MessageVideoContentView()
    let imageHeight = imageView.height(for: image, width: 240)
    let videoHeight = videoView.height(for: video, width: 240)
    let fileView = MessageFileContentView()
    let receiptWidth = MessageReadReceiptsView.width(for: 3)
    #expect(receiptWidth == 38)

    // Reconfigure the same file view at larger and smaller sizes, then restore the default.
    for size in [26, 10, 13] {
      defaults.set(size, forKey: "fontSize")
      let fileHeight = fileView.height(for: file, width: 240)
      fileView.frame = NSRect(x: 0, y: 0, width: 240, height: fileHeight)
      fileView.configure(file: file, matrixClient: nil)
      fileView.layoutSubtreeIfNeeded()
      let button = try #require(fileView.subviews.first { $0 is NSButton })
      let icon = try #require(button.subviews.compactMap { $0 as? NSImageView }.first)
      #expect(abs(icon.frame.width - TimelineTypography.scaled(36)) < 1)
      #expect(abs(icon.frame.height - TimelineTypography.scaled(36)) < 1)
      #expect(fileHeight >= ceil(TimelineTypography.scaled(36)))
      #expect(icon.frame.maxY <= button.bounds.maxY + 1)

      let profile = MessageProfileRowView()
      profile.frame = NSRect(x: 0, y: 0, width: 240, height: MessageProfileRowView.rowHeight)
      profile.layoutSubtreeIfNeeded()
      #expect(abs(profile.profilePicture.frame.width - TimelineTypography.scaled(32)) < 1)
      #expect(abs(profile.profilePicture.frame.height - TimelineTypography.scaled(32)) < 1)
      #expect(profile.profilePicture.frame.maxY <= profile.bounds.maxY + 1)

      let content = MessageTextContentView()
      let message = MessageRowView(contentKind: .text, contentView: content)
      message.frame = NSRect(x: 0, y: 0, width: 240, height: 100)
      message.layoutSubtreeIfNeeded()
      let timestamp = try #require(message.subviews.compactMap { $0 as? NSTextField }.first)
      let avatarRect = profile.profilePicture.alignmentRect(forFrame: profile.profilePicture.frame)
      let timestampRect = timestamp.alignmentRect(forFrame: timestamp.frame)
      let nameRect = profile.name.alignmentRect(forFrame: profile.name.frame)
      let contentRect = content.alignmentRect(forFrame: content.frame)
      #expect(abs(avatarRect.maxX - timestampRect.maxX) < 1)
      #expect(abs(nameRect.minX - contentRect.minX) < 1)
      #expect(
        abs(MessageReadReceiptsView.width(for: 3) - TimelineTypography.scaled(receiptWidth)) < 0.01)
      #expect(MessageReadReceiptsView.rowHeight >= ceil(TimelineTypography.scaled(14)))
      #expect(imageView.height(for: image, width: 240) == imageHeight)
      #expect(videoView.height(for: video, width: 240) == videoHeight)
    }
  }

  private func textFields(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { child in
      if let field = child as? NSTextField { return [field] }
      return textFields(in: child)
    }
  }
}

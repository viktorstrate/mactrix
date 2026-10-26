import AppKit
import MatrixRustSDK
import Testing
import UniformTypeIdentifiers

@testable import MactrixApp

@MainActor
struct ChatComposerContainerTests {
  @Test func optionalSectionsCollapseAndReplyHasPadding() {
    let container = makeContainer()
    let width: CGFloat = 400
    let editorHeight = container.editor.height(for: width - 32)
    let replyHeight = MessageReplyPreviewView.height(for: .pending, width: width - 52)

    for (hasReply, hasAttachments) in [
      (false, false), (true, false), (true, true),
      (false, true), (false, false), (true, true), (false, false),
    ] {
      container.setReply(details: hasReply ? .pending : nil)
      container.setAttachments(hasAttachments ? [attachment()] : [])
      let optionalCount = (hasReply ? 1 : 0) + (hasAttachments ? 1 : 0)
      let expected = ceil(
        editorHeight + 10 + (optionalCount > 0 ? 8 : 0)
          + CGFloat(max(0, optionalCount - 1)) * 8 + (hasReply ? replyHeight : 0)
          + (hasAttachments ? ComposerAttachmentPreviewStrip.height : 0))
      #expect(container.height(for: width) == expected)
      layout(container, width: width)
      let editorRect = container.editor.convert(container.editor.bounds, to: container)
      #expect(abs(editorRect.minX - 16) < 0.01)
      #expect(abs(editorRect.minY - 10) < 0.01)
      #expect(abs(editorRect.height - editorHeight) < 0.01)
      #expect(container.editor.textContainerInset == DynamicTextView.padding)
      for x in [editorRect.minX + 1, editorRect.maxX - 1] {
        let point = NSPoint(x: x, y: editorRect.maxY - 1)
        #expect(container.hitTest(point) === container.editor)
      }
      if hasReply {
        let rect = container.reply.convert(container.reply.bounds, to: container)
        #expect(abs(rect.minX - 26) < 0.01)
        #expect(abs(rect.width - (width - 52)) < 0.01)
        #expect(abs(container.bounds.maxY - rect.maxY - 8) < 0.01)
        #expect(abs(rect.height - replyHeight) < 0.01)
      }
      if hasAttachments {
        let rect = container.attachments.convert(container.attachments.bounds, to: container)
        #expect(abs(rect.minY - editorRect.maxY) < 0.01)
        if hasReply {
          let replyRect = container.reply.convert(container.reply.bounds, to: container)
          #expect(abs(replyRect.minY - rect.maxY - 8) < 0.01)
        }
      } else if hasReply {
        let rect = container.reply.convert(container.reply.bounds, to: container)
        #expect(abs(rect.minY - editorRect.maxY) < 0.01)
      }
    }
  }

  @Test func wrappedContentUsesPaddedWidthAndWidthProbesDoNotMutateEditor() {
    let container = makeContainer()
    container.editor.string = String(repeating: "Wrapping editor text. ", count: 12)
    let details = EmbeddedEventDetails.error(
      message: String(repeating: "Long reply content. ", count: 20))
    container.setReply(details: details)
    for width: CGFloat in [240, 600, 320] {
      layout(container, width: width)
      let replyHeight = MessageReplyPreviewView.height(for: details, width: width - 52)
      #expect(abs(container.reply.frame.height - replyHeight) < 0.01)
      #expect(abs(container.editor.frame.height - container.editor.height(for: width - 32)) < 0.01)
      let frame = container.editor.frame
      let textContainerSize = unsafe container.editor.textContainer?.containerSize
      let height = container.height(for: width)
      #expect(container.height(for: 180) > container.height(for: 800))
      #expect(container.editor.frame == frame)
      #expect(unsafe container.editor.textContainer?.containerSize == textContainerSize)
      #expect(container.height(for: width) == height)
    }
  }

  @Test func constrainedParentCanShrinkComposer() {
    let container = makeContainer()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 2000))
    container.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(container)
    let trailing = container.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
    // Match SwiftUI's encapsulated width priority, not a required frame override.
    trailing.priority = NSLayoutConstraint.Priority(500)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      trailing,
      container.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
    container.editor.string = String(repeating: "Wrapping editor text. ", count: 30)
    let details = EmbeddedEventDetails.error(
      message: String(repeating: "Long reply content. ", count: 20))
    for (hasReply, hasAttachments) in [
      (false, false), (true, false), (true, true), (false, true), (false, false),
    ] {
      container.setReply(details: hasReply ? details : nil)
      container.setAttachments(hasAttachments ? (0..<8).map { _ in attachment() } : [])
      for width: CGFloat in [800, 400, 250, 600, 250] {
        parent.setFrameSize(NSSize(width: width, height: 2000))
        parent.layoutSubtreeIfNeeded()
        let editorRect = container.editor.convert(container.editor.bounds, to: container)
        #expect(abs(container.frame.width - width) < 0.01)
        #expect(abs(editorRect.minX - 16) < 0.01)
        #expect(abs(editorRect.maxX - (width - 16)) < 0.01)
        #expect(abs(container.frame.height - container.height(for: width)) < 0.01)
        #expect(abs(editorRect.height - container.editor.height(for: width - 32)) < 0.01)
        for x in [editorRect.minX + 1, editorRect.maxX - 1] {
          #expect(container.hitTest(NSPoint(x: x, y: editorRect.maxY - 1)) === container.editor)
        }
        if hasAttachments {
          let rect = container.attachments.convert(container.attachments.bounds, to: container)
          #expect(abs(rect.width - (width - 32)) < 0.01)
          #expect(abs(rect.minY - editorRect.maxY) < 0.01)
          #expect(container.attachments.documentView!.frame.width >= rect.width)
        }
        if hasReply {
          let rect = container.reply.convert(container.reply.bounds, to: container)
          #expect(abs(rect.width - (width - 52)) < 0.01)
          #expect(
            abs(rect.height - MessageReplyPreviewView.height(for: details, width: width - 52))
              < 0.01)
          let preceding =
            hasAttachments
            ? container.attachments.convert(container.attachments.bounds, to: container)
            : editorRect
          #expect(abs(rect.minY - preceding.maxY - (hasAttachments ? 8 : 0)) < 0.01)
        }
      }
    }
  }


  private func makeContainer() -> ChatComposerContainer {
    let container = ChatComposerContainer()
    container.editor.font = .systemFont(ofSize: 13)
    container.editor.textContainerInset = DynamicTextView.padding
    container.editor.isHorizontallyResizable = false
    unsafe container.editor.textContainer?.widthTracksTextView = true
    return container
  }

  private func layout(_ container: ChatComposerContainer, width: CGFloat) {
    container.setFrameSize(NSSize(width: width, height: container.height(for: width)))
    container.layoutSubtreeIfNeeded()
  }

  private func attachment() -> ComposerAttachment {
    ComposerAttachment(
      sourceURL: URL(fileURLWithPath: "/tmp/composer-layout-test.pdf"),
      filename: "test.pdf", contentType: .pdf, byteCount: 1, kind: .file,
      storageOwnership: .externalUserFile,
      deduplicationIdentity: .absolutePath("/tmp/composer-layout-test.pdf"))
  }
}

import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct ChatInputView: View {
  @Environment(\.accessibilityReduceTransparency) var reduceTransparency

  let room: Room
  let timeline: LiveTimeline
  @Bindable var composer: ChatComposerState
  @AppStorage("fontSize") var fontSize: Int = 13
  @State private var isAttachmentDropTargeted = false

  private func ingestFileURLs(_ urls: [URL]) async {
    let attachments = await ComposerAttachmentImporter.importFiles(at: urls)
    guard !attachments.isEmpty else { return }
    composer.addAttachments(attachments)
    composer.requestTextFocus()
  }

  private func handlePaste(from pasteboard: NSPasteboard) -> Bool {
    let fileURLs =
      pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
      ) as? [URL] ?? []
    if !fileURLs.isEmpty {
      Task { await ingestFileURLs(fileURLs) }
      return true
    }

    guard let imageType = pasteboard.availableType(from: [.png, .tiff]),
      let imageData = pasteboard.data(forType: imageType)
    else { return false }

    Task {
      do {
        let attachment = try await ComposerAttachmentImporter.importClipboardImage(
          pngData: imageType == .png ? imageData : nil,
          tiffData: imageType == .tiff ? imageData : nil)
        composer.addAttachments([attachment])
        composer.requestTextFocus()
      } catch {
        Logger.composerAttachment.error("Unable to import clipboard image: \(error)")
      }
    }
    return true
  }

  private func chatInputChanged() async {
    await composer.saveDraft(room: room, timeline: timeline)
    if !composer.text.isEmpty {
      do {
        try await room.typingNotice(isTyping: !composer.text.isEmpty)
      } catch {
        Logger.viewCycle.warning("Failed to send typing notice: \(error)")
      }
    }
  }

  var replyEmbeddedDetails: EmbeddedEventDetails? {
    guard let replyTarget = composer.replyTarget else { return nil }

    return .ready(
      content: replyTarget.content, sender: replyTarget.sender,
      senderProfile: replyTarget.senderProfile, timestamp: replyTarget.timestamp,
      eventOrTransactionId: replyTarget.eventOrTransactionId
    )
  }

  var content: some View {
    VStack(alignment: .leading) {
      if let replyEmbeddedDetails {
        EmbeddedMessageView(embeddedEvent: replyEmbeddedDetails) {
          composer.cancelReply()
        }
        .padding([.horizontal, .top], 10)
      }

      ComposerAttachmentPreviewStrip(attachments: composer.attachments) { attachmentID in
        composer.removeAttachment(id: attachmentID)
      }
      .padding(.top, replyEmbeddedDetails == nil ? 10 : 0)

      ChatTextView(
        text: $composer.text,
        placeholder: "Message \(room.displayName() ?? "room")",
        disabled: !composer.isDraftLoaded,
        focusRequest: composer.focusRequest,
        onSubmit: {
          Task {
            guard let timeline = timeline.timeline else { return }
            await composer.sendMessage(timeline: timeline)
          }
        },
        onAttachmentPaste: handlePaste
      )
    }
    .font(.system(size: .init(fontSize)))
    .task(id: composer.draftRevision) {
      await chatInputChanged()
    }
    .task(id: timeline.timeline != nil) {
      // we need the timeline to be populated before we load a draft
      // (in case the draft holds a reply)
      await composer.loadDraft(room: room, timeline: timeline)
    }
  }

  @available(macOS 26.0, *)
  var tahoeView: some View {
    content
      .glassEffect(in: .rect(cornerRadius: 16.0))
      .background(dropHighlight)
      .padding(.horizontal)
      .padding(.bottom, 10)
  }

  var oldView: some View {
    content
      .background(Color(NSColor.textBackgroundColor))
      .cornerRadius(4)
      .overlay(
        RoundedRectangle(cornerRadius: 16.0)
          .stroke(
            isAttachmentDropTargeted ? Color.accentColor : Color(NSColor.separatorColor),
            lineWidth: isAttachmentDropTargeted ? 2 : 1)
      )
      .background(dropHighlight)
      .padding(.horizontal)
      .padding(.bottom, 10)
  }

  private var dropHighlight: some View {
    RoundedRectangle(cornerRadius: 16.0)
      .fill(Color.accentColor.opacity(isAttachmentDropTargeted ? 0.10 : 0))
      .overlay(
        RoundedRectangle(cornerRadius: 16.0)
          .stroke(Color.accentColor.opacity(isAttachmentDropTargeted ? 0.7 : 0), lineWidth: 2)
      )
      .allowsHitTesting(false)
  }

  private func dropTarget<Content: View>(for view: Content) -> some View {
    view
      .contentShape(Rectangle())
      .dropDestination(for: URL.self) { urls, _ in
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        Task { await ingestFileURLs(fileURLs) }
        return true
      } isTargeted: { isTargeted in
        isAttachmentDropTargeted = isTargeted
      }
  }

  var body: some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      dropTarget(for: tahoeView)
    } else {
      dropTarget(for: oldView)
    }
  }
}

/* #Preview {
     ChatInputView()
 } */

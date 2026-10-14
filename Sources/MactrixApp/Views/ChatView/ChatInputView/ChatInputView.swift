import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View, DropDelegate {
  @Environment(\.accessibilityReduceTransparency) var reduceTransparency

  let room: Room
  let timeline: LiveTimeline
  @Bindable var composer: ChatComposerState
  @AppStorage("fontSize") var fontSize: Int = 13
  @State private var isAttachmentDropTargeted = false

  private func handlePaste(from pasteboard: NSPasteboard) -> Bool {
    let inputs = ComposerAttachmentInputAdapter.inputs(from: pasteboard)
    guard !inputs.isEmpty else { return false }
    Task {
      var attachments: [ComposerAttachment] = []
      for input in inputs {
        do {
          attachments.append(try await ComposerAttachmentImporter.importInput(input))
          Logger.composerAttachment.debug("Pasted attachment import succeeded")
        } catch {
          Logger.composerAttachment.error("Unable to import pasted attachment: \(error)")
        }
      }
      composer.addAttachments(attachments)
      if !attachments.isEmpty { composer.requestTextFocus() }
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
        onCanPasteAttachments: ComposerAttachmentInputAdapter.canImportAttachments,
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
      .onDrop(of: [.fileURL, .image, .pdf], delegate: self)
  }

  private func dropProviders(for info: DropInfo)
    -> (providers: [NSItemProvider], mode: ComposerAttachmentInputAdapter.DropMode)
  {
    let files = info.itemProviders(for: [.fileURL])
    return files.isEmpty ? (info.itemProviders(for: [.item]), .raw) : (files, .files)
  }

  func validateDrop(info: DropInfo) -> Bool {
    let selection = dropProviders(for: info)
    return ComposerAttachmentInputAdapter.canImportAttachments(
      from: selection.providers, mode: selection.mode)
  }

  func dropEntered(info: DropInfo) {
    isAttachmentDropTargeted = validateDrop(info: info)
  }

  func dropExited(info: DropInfo) {
    isAttachmentDropTargeted = false
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    let accepted = validateDrop(info: info)
    return DropProposal(operation: accepted ? .copy : .forbidden)
  }

  func performDrop(info: DropInfo) -> Bool {
    isAttachmentDropTargeted = false
    let selection = dropProviders(for: info)
    return ComposerAttachmentInputAdapter.startImportProviders(
      selection.providers, mode: selection.mode
    ) { attachments in
      composer.addAttachments(attachments)
      if !attachments.isEmpty { composer.requestTextFocus() }
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

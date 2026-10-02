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

  func sendMessage() async {
    guard !composer.text.isEmpty else { return }
    guard let innerTimeline = timeline.timeline else { return }

    let msg = messageEventContentFromMarkdown(md: composer.text)

    do {
      if let replyTarget = composer.replyTarget {
        _ = try await innerTimeline.sendReply(
          msg: msg, eventId: replyTarget.eventOrTransactionId.id
        )
      } else {
        _ = try await innerTimeline.send(msg: msg)
      }
    } catch {
      Logger.viewCycle.error("failed to send message: \(error)")
    }

    composer.finishSending()
  }

  private func saveDraft() async {
    guard composer.isDraftLoaded else { return }  // avoid overwriting a draft before restoration
    if composer.text.isEmpty, composer.replyTarget == nil {
      Logger.viewCycle.debug("clearing draft")
      do {
        try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
      } catch {
        Logger.viewCycle.error("failed to clear draft: \(error)")
      }
      return
    }

    let draftType: ComposerDraftType
    if let replyTarget = composer.replyTarget {
      draftType = .reply(eventId: replyTarget.eventOrTransactionId.id)
    } else {
      draftType = .newMessage
    }
    let draft = ComposerDraft(
      plainText: composer.text,
      htmlText: nil,
      draftType: draftType,
      attachments: []
    )
    do {
      try await room.saveComposerDraft(draft: draft, threadRoot: timeline.focusedThreadId)
    } catch {
      Logger.viewCycle.error("failed save draft: \(error)")
    }
  }

  private func loadDraft() async {
    guard !composer.isDraftLoaded else { return }  // don't load a draft more than once
    do {
      guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId)
      else {
        // no draft to load
        composer.completeDraftRestoration()
        return
      }
      composer.text = draft.plainText
      switch draft.draftType {
      case .reply(let eventId):
        // we need a timeline to be able to populate the reply; return false so we can try again
        guard let innerTimeline = timeline.timeline else { return }

        do {
          let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
          composer.restoreReply(to: item)
        } catch {
          Logger.viewCycle.error("failed to resolve reply target: \(error)")
        }
      case .newMessage, .edit:
        // nothing to do
        break
      }
    } catch {
      Logger.viewCycle.error("failed to load draft: \(error)")
    }
    composer.completeDraftRestoration()
  }

  private func chatInputChanged() async {
    guard composer.isDraftLoaded else { return }  // avoid working on a draft being restored
    if !composer.text.isEmpty {
      do {
        try await room.typingNotice(isTyping: !composer.text.isEmpty)
      } catch {
        Logger.viewCycle.warning("Failed to send typing notice: \(error)")
      }
    }
    await saveDraft()
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
        }.padding([.horizontal, .top], 10)
      }

      ComposerAttachmentPreviewStrip(attachments: composer.attachments) { attachmentID in
        composer.removeAttachment(id: attachmentID)
      }
      .padding(.horizontal, 10)
      .padding(.top, replyEmbeddedDetails == nil ? 10 : 0)

      ChatTextView(
        text: $composer.text,
        placeholder: "Message \(room.displayName() ?? "room")",
        disabled: !composer.isDraftLoaded,
        focusRequest: composer.focusRequest,
        onSubmit: { Task { await sendMessage() } }
      )
    }
    .font(.system(size: .init(fontSize)))
    .task(id: composer.text) {
      await chatInputChanged()
    }
    .task(id: composer.replyTarget?.eventOrTransactionId) {
      await saveDraft()
    }
    .task(id: timeline.timeline != nil) {
      // we need the timeline to be populated before we load a draft
      // (in case the draft holds a reply)
      await loadDraft()
    }
  }

  @available(macOS 26.0, *)
  var tahoeView: some View {
    content
      .glassEffect(in: .rect(cornerRadius: 16.0))
      .padding(.horizontal)
      .padding(.bottom, 10)
  }

  var oldView: some View {
    content
      .background(Color(NSColor.textBackgroundColor))
      .cornerRadius(4)
      .overlay(
        RoundedRectangle(cornerRadius: 16.0)
          .stroke(Color(NSColor.separatorColor), lineWidth: 1)
      )
      .padding(.horizontal)
      .padding(.bottom, 10)
  }

  var body: some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      tahoeView
    } else {
      oldView
    }
  }
}

/* #Preview {
     ChatInputView()
 } */

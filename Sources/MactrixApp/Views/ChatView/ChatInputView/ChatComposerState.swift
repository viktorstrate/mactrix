import Foundation
import MatrixIntegration
import MatrixRustSDK
import OSLog

@MainActor
struct ComposerSubmissionSnapshot {
  let text: String
  let replyTarget: EventTimelineItem?
  let replyEventIdentifier: String?
  let attachments: [ComposerAttachment]
}

@MainActor @Observable
final class ChatComposerState {
  var text = "" {
    didSet { draftRevision += 1 }
  }
  private(set) var replyTarget: EventTimelineItem?
  private(set) var attachments: [ComposerAttachment] = []
  private(set) var isDraftLoaded = false
  private var isDraftRestoring = false
  private(set) var draftRevision = 0
  private(set) var focusRequest = 0
  private(set) var isSending = false

  var canSend: Bool {
    !text.isEmpty || !attachments.isEmpty
  }

  func beginReply(to event: EventTimelineItem) {
    replyTarget = event
    draftRevision += 1
    requestTextFocus()
  }

  func restoreReply(to event: EventTimelineItem) {
    replyTarget = event
    draftRevision += 1
  }

  func cancelReply() {
    guard replyTarget != nil else { return }
    replyTarget = nil
    draftRevision += 1
  }

  func addAttachments(_ newAttachments: [ComposerAttachment]) {
    var identities = Set(attachments.map(\.deduplicationIdentity))
    let uniqueAttachments = newAttachments.filter {
      identities.insert($0.deduplicationIdentity).inserted
    }
    guard !uniqueAttachments.isEmpty else { return }
    attachments.append(contentsOf: uniqueAttachments)
    draftRevision += 1
  }

  func removeAttachment(id: ComposerAttachment.ID) {
    guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
    let attachment = attachments.remove(at: index)
    draftRevision += 1
    cleanupIfOwned(attachment)
  }

  func requestTextFocus() {
    focusRequest += 1
  }

  func captureSubmission() -> ComposerSubmissionSnapshot {
    ComposerSubmissionSnapshot(
      text: text,
      replyTarget: replyTarget,
      replyEventIdentifier: replyTarget?.eventOrTransactionId.id,
      attachments: attachments,
    )
  }

  func sendMessage(timeline: Timeline) async {
    guard !isSending else { return }
    isSending = true
    defer { isSending = false }

    let snapshot = captureSubmission()

    switch snapshot.attachments.count {
    case 0:
      guard !snapshot.text.isEmpty else { return }
      do {
        let message = messageEventContentFromMarkdown(md: snapshot.text)
        if let replyID = snapshot.replyEventIdentifier {
          _ = try await timeline.sendReply(msg: message, eventId: replyID)
        } else {
          _ = try await timeline.send(msg: message)
        }
        finishSending(snapshot: snapshot)
      } catch {
        Logger.viewCycle.error("failed to send message: \(error)")
      }

    case 1:
      guard let attachment = snapshot.attachments.first else { return }
      do {
        let upload = try await ComposerMediaPreparation.prepare(
          attachment: attachment, caption: snapshot.text, replyID: snapshot.replyEventIdentifier)
        let joinHandle: SendAttachmentJoinHandle
        switch upload.media {
        case .image(let info, let thumbnailSource):
          joinHandle = try timeline.sendImage(
            params: upload.parameters, thumbnailSource: thumbnailSource, imageInfo: info)
        case .video(let info, let thumbnailSource):
          joinHandle = try timeline.sendVideo(
            params: upload.parameters, thumbnailSource: thumbnailSource, videoInfo: info)
        case .audio(let info):
          joinHandle = try timeline.sendAudio(params: upload.parameters, audioInfo: info)
        case .file(let info):
          joinHandle = try timeline.sendFile(params: upload.parameters, fileInfo: info)
        }

        try await joinHandle.join()
        finishSending(snapshot: snapshot, cleanupAttachments: true)
      } catch {
        Logger.composerAttachment.error(
          "failed to enqueue attachment \(attachment.filename): \(error)")
      }

    default:
      do {
        let preparedAttachments = try await withThrowingTaskGroup { group in
          for (i, attachment) in snapshot.attachments.enumerated() {
            group.addTask {
              let prepared = try await ComposerMediaPreparation.prepare(
                attachment: attachment, caption: "", replyID: nil
              )
              return (i, prepared)
            }
          }

          var result = Array<GalleryItemInfo?>.init(
            repeating: nil, count: snapshot.attachments.count)
          for try await (i, prepared) in group {
            result[i] = prepared.asGalleryItemInfo
          }
          return result.compactMap { $0 }
        }

        let joinHandle = try timeline.sendGallery(
          params: GalleryUploadParameters(
            caption: snapshot.text,
            formattedCaption: nil,
            mentions: nil,
            inReplyTo: snapshot.replyEventIdentifier,
          ),
          itemInfos: preparedAttachments,
        )

        try await joinHandle.join()
        finishSending(snapshot: snapshot, cleanupAttachments: true)
      } catch {
        Logger.composerAttachment.error("failed to enqueue attachments: \(error)")
      }
    }
  }

  /// Clears only content included in `snapshot`, preserving edits made while submission was prepared.
  /// Set `cleanupAttachments` to false when the sending layer needs to retain temporary sources.
  func finishSending(
    snapshot: ComposerSubmissionSnapshot, cleanupAttachments: Bool = true
  ) {
    if text == snapshot.text {
      text = ""
    }
    if replyTarget?.eventOrTransactionId.id == snapshot.replyEventIdentifier {
      replyTarget = nil
      draftRevision += 1
    }

    let capturedIDs = Set(snapshot.attachments.map(\.id))
    let submittedAttachments = attachments.filter { capturedIDs.contains($0.id) }
    guard !submittedAttachments.isEmpty else { return }
    attachments.removeAll { capturedIDs.contains($0.id) }
    draftRevision += 1

    if cleanupAttachments {
      submittedAttachments.forEach(cleanupIfOwned)
    }
  }

  func saveDraft(room: Room, timeline: LiveTimeline) async {
    guard isDraftLoaded else { return }  // avoid overwriting a draft before restoration

    if text.isEmpty, replyTarget == nil, attachments.isEmpty {
      Logger.viewCycle.debug("clearing draft")
      do {
        try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
      } catch {
        Logger.viewCycle.error("failed to clear draft: \(error)")
      }
      return
    }

    let draftType: ComposerDraftType
    if let replyTarget {
      draftType = .reply(eventId: replyTarget.eventOrTransactionId.id)
    } else {
      draftType = .newMessage
    }
    let draft = ComposerDraft(
      plainText: text,
      htmlText: nil,
      draftType: draftType,
      attachments: attachments.map(\.draftAttachment)
    )
    do {
      try await room.saveComposerDraft(draft: draft, threadRoot: timeline.focusedThreadId)
    } catch {
      Logger.viewCycle.error("failed save draft: \(error)")
    }
  }

  func loadDraft(room: Room, timeline: LiveTimeline) async {
    guard let innerTimeline = timeline.timeline else { return }
    guard beginDraftRestoration() else { return }

    do {
      guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId)
      else {
        completeDraftRestoration()
        return
      }
      text = draft.plainText
      switch draft.draftType {
      case .reply(let eventId):
        do {
          let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
          restoreReply(to: item)
        } catch {
          Logger.viewCycle.error("failed to resolve reply target: \(error)")
        }
      case .newMessage, .edit:
        break
      }

      var discardedAttachment = false
      for draftAttachment in draft.attachments {
        let attachmentCount = attachments.count
        do {
          let attachment = try await ComposerAttachment.restoreDraftAttachment(draftAttachment)
          addAttachments([attachment])
          if attachments.count == attachmentCount {
            discardedAttachment = true  // duplicate entries are saved only once
            if attachment.storageOwnership == .appOwnedTemporaryFile {
              try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment)
            }
          }
        } catch {
          discardedAttachment = true
          Logger.composerAttachment.warning("Discarding unavailable draft attachment: \(error)")
        }
      }
      completeDraftRestoration()
      if discardedAttachment {
        await saveDraft(room: room, timeline: timeline)
      }
    } catch {
      Logger.viewCycle.error("failed to load draft: \(error)")
      completeDraftRestoration()
    }
  }

  /// Clears the entire composer, including app-owned temporary attachment files.
  func reset() {
    let removedAttachments = attachments
    text = ""
    replyTarget = nil
    attachments = []
    draftRevision += 1
    removedAttachments.forEach(cleanupIfOwned)
  }

  /// Starts a single draft restoration. Returns false while another restoration is in progress.
  private func beginDraftRestoration() -> Bool {
    guard !isDraftLoaded, !isDraftRestoring else { return false }
    isDraftRestoring = true
    return true
  }

  private func completeDraftRestoration() {
    isDraftRestoring = false
    isDraftLoaded = true
  }

  private func cleanupIfOwned(_ attachment: ComposerAttachment) {
    guard attachment.storageOwnership == .appOwnedTemporaryFile else { return }
    try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment)
  }
}

import Foundation
import MatrixRustSDK

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
  func beginDraftRestoration() -> Bool {
    guard !isDraftLoaded, !isDraftRestoring else { return false }
    isDraftRestoring = true
    return true
  }

  /// Allows restoration to retry when a dependency, such as the timeline, is unavailable.
  func deferDraftRestoration() {
    isDraftRestoring = false
  }

  func completeDraftRestoration() {
    isDraftRestoring = false
    isDraftLoaded = true
  }

  func finishSending() {
    finishSending(snapshot: captureSubmission())
  }

  private func cleanupIfOwned(_ attachment: ComposerAttachment) {
    guard attachment.storageOwnership == .appOwnedTemporaryFile else { return }
    try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment)
  }
}

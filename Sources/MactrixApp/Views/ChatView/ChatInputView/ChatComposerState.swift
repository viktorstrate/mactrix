import MatrixRustSDK
import Observation

@MainActor @Observable
final class ChatComposerState {
  var text = ""
  private(set) var replyTarget: EventTimelineItem?
  private(set) var isDraftLoaded = false
  private(set) var focusRequest = 0

  func beginReply(to event: EventTimelineItem) {
    replyTarget = event
    focusRequest += 1
  }

  func restoreReply(to event: EventTimelineItem) {
    replyTarget = event
  }

  func cancelReply() {
    replyTarget = nil
  }

  func completeDraftRestoration() {
    isDraftLoaded = true
  }

  func finishSending() {
    text = ""
    replyTarget = nil
  }
}

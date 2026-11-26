import AppKit
import MatrixRustSDK

/// Whether a message the user sent is still on its way to the server, or failed to get there.
///
/// Messages that reached the server, and other people's messages, have no status.
enum MessageSendStatus: Equatable {
  /// The message is queued or being sent.
  case queued
  /// Sending failed. The message stays queued until it's retried or deleted.
  case failed(reason: String)

  init?(_ state: MatrixRustSDK.EventSendState?) {
    switch state {
    case .notSentYet:
      self = .queued
    case .sendingFailed(let error, let isRecoverable):
      // A recoverable failure is a network or server error, which the error itself doesn't
      // describe any better.
      self = .failed(
        reason: isRecoverable
          ? String(localized: "The server couldn't be reached.") : Self.reason(for: error))
    case .sent, nil:
      return nil
    }
  }

  var symbolName: String {
    switch self {
    case .queued: "clock"
    case .failed: "exclamationmark.circle.fill"
    }
  }

  var tintColor: NSColor {
    switch self {
    case .queued: .secondaryLabelColor
    case .failed: .systemRed
    }
  }

  var toolTip: String {
    switch self {
    case .queued:
      String(localized: "Not sent yet")
    case .failed(let reason):
      String(localized: "Not sent. \(reason) Click to retry or delete.")
    }
  }

  private static func reason(for error: MatrixRustSDK.QueueWedgeError) -> String {
    switch error {
    case .insecureDevices:
      String(localized: "Some devices in this room aren't verified.")
    case .identityViolations:
      String(localized: "Someone in this room changed their identity.")
    case .crossVerificationRequired:
      String(localized: "Verify this session to send messages.")
    case .expiredAccessToken:
      String(localized: "Your session expired.")
    case .missingMediaContent:
      String(localized: "The attachment is no longer available.")
    case .invalidMimeType:
      String(localized: "The attachment's file type isn't recognized.")
    case .genericApiError(let message):
      message
    }
  }
}

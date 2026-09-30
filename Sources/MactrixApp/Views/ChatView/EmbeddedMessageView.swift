import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct EmbeddedMessageView: View {
  let embeddedEvent: MatrixRustSDK.EmbeddedEventDetails
  let action: () -> Void

  var body: some View {
    switch embeddedEvent {
    case .unavailable, .pending:
      MactrixUI.MessageReplyView(
        username: "loading@username.org",
        message: "Phasellus sit amet purus ac enim semper convallis. Nullam a gravida libero.",
        action: action
      )
      .redacted(reason: .placeholder)
    case .ready(let content, let sender, let senderProfile, _, _):
      MactrixUI.MessageReplyView(
        username: {
          if case .ready(let name, _, _, _, _) = senderProfile, let name { return name }
          return sender
        }(),
        message: content.userInterfaceText,
        action: action
      )
    case .error(let message):
      Text("error: \(message)")
    }
  }
}

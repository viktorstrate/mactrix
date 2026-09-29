import MatrixRustSDK
import SwiftUI
import MactrixUI
import MatrixIntegration

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
        case let .ready(content, sender, senderProfile, _, _):
            MactrixUI.MessageReplyView(
                username: {
                    if case let .ready(name, _, _, _, _) = senderProfile, let name { return name }
                    return sender
                }(),
                message: content.userInterfaceText,
                action: action
            )
        case let .error(message):
            Text("error: \(message)")
        }
    }
}

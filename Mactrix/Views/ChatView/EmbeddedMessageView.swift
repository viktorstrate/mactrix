import MatrixRustSDK
import SwiftUI
import UI

struct EmbeddedMessageView: View {
    let embeddedEvent: MatrixRustSDK.EmbeddedEventDetails
    let action: () -> Void

    var body: some View {
        switch embeddedEvent {
        case .unavailable, .pending:
            UI.MessageReplyView(
                username: "loading@username.org",
                message: "Phasellus sit amet purus ac enim semper convallis. Nullam a gravida libero.",
                action: action
            )
            .redacted(reason: .placeholder)
        case let .ready(content, sender, senderProfile, _, _):
            UI.MessageReplyView(
                username: {
                    if case let .ready(name, _, _) = senderProfile, let name { return name }
                    return sender
                }(),
                message: content.description,
                action: action
            )
        case let .error(message):
            Text("error: \(message)")
        }
    }
}

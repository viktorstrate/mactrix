import MatrixRustSDK
import Models
import SwiftUI
import UI

struct ChatMessageView: View, UI.MessageEventActions {
    @Environment(AppState.self) private var appState

    let timeline: MatrixRustSDK.Timeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MsgLikeContent

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    func toggleReaction(key: String) {
        Task {
            do {
                let _ = try await timeline?.toggleReaction(itemId: event.eventOrTransactionId, key: key)
            } catch {
                print("Failed to toggle reaction: \(error)")
            }
        }
    }

    func reply() {}

    func replyInThread() {}

    func pin() {
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do {
                let _ = try await timeline?.pinEvent(eventId: eventId)
            } catch {
                print("Failed to ping message: \(error)")
            }
        }
    }

    @ViewBuilder
    var message: some View {
        switch msg.kind {
        case let .message(content: content):
            switch content.msgType {
            case let .emote(content: content):
                Text("Emote: \(content.body)").textSelection(.enabled)
            case let .image(content: content):
                MessageImageView(content: content)
            case let .audio(content: content):
                Text("Audio: \(content.caption ?? "no caption") \(content.filename)").textSelection(.enabled)
            case let .video(content: content):
                Text("Video: \(content.caption ?? "no caption") \(content.filename)").textSelection(.enabled)
            case let .file(content: content):
                Text("File: \(content.caption ?? "no caption") \(content.filename)").textSelection(.enabled)
            case let .gallery(content: content):
                Text("Gallery: \(content.body)").textSelection(.enabled)
            case let .notice(content: content):
                Text("Notice: \(content.body)").textSelection(.enabled)
            case let .text(content: content):
                Text(content.body).textSelection(.enabled)
            case let .location(content: content):
                Text("Location: \(content.body) \(content.geoUri)").textSelection(.enabled)
            case let .other(msgtype: msgtype, body: body):
                Text("Other: \(msgtype) \(body)").textSelection(.enabled)
            }
        case .sticker(body: let body, info: _, source: _):
            Text("Sticker: \(body)").textSelection(.enabled)
        case .poll(question: let question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _, hasBeenEdited: _):
            Text("Poll: \(question)").textSelection(.enabled)
        case .redacted:
            Text("Message redacted")
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .unableToDecrypt(msg: _):
            Text("Unable to decrypt")
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .other(eventType: _):
            Text("Custom event").textSelection(.enabled)
        }
    }

    var body: some View {
        UI.MessageEventView(event: event, reactions: msg.reactions, actions: self, imageLoader: appState.matrixClient) {
            message
        }
    }
}

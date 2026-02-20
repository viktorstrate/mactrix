import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct ChatMessageView: View, UI.MessageEventActions {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @AppStorage("fontSize") private var fontSize = 13

    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent
    let includeProfileHeader: Bool

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    func toggleReaction(key: String) {
        Task {
            guard let innerTimeline = timeline?.timeline else { return }
            do {
                let reactionWasAdded = try await innerTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
                Logger.viewCycle.debug("reaction \(reactionWasAdded ? "added" : "removed"): \(key)")
            } catch {
                Logger.viewCycle.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    func reply() {
        Logger.viewCycle.info("Reply to event: \(event.eventOrTransactionId.id)")
        timeline?.sendReplyTo = event
    }

    func replyInThread() {
        windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
    }

    func pin() {
        Logger.viewCycle.info("Pinning message")
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do {
                let _ = try await timeline?.timeline?.pinEvent(eventId: eventId)
            } catch {
                Logger.viewCycle.error("Failed to ping message: \(error)")
            }
        }
    }

    func focusUser() {
        Logger.viewCycle.info("Focusing user \(event.sender)")
        windowState.focusUser(userId: event.sender)
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
                MessageFileView(content: content)
            case let .gallery(content: content):
                Text("Gallery: \(content.body)").textSelection(.enabled)
            case let .notice(content: content):
                Text(content.body.formatAsMarkdown)
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            case let .text(content: content):
                Text(content.body.formatAsMarkdown).textSelection(.enabled)
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
        case let .other(eventType: eventType):
            let eventText = eventType.description

            Text("Custom event: \(eventText)").textSelection(.enabled)
        }
    }

    var isEventFocused: Bool {
        return timeline?.focusedTimelineEventId == event.eventOrTransactionId
    }

    var ownUserId: String {
        do {
            return try appState.matrixClient?.client.userId() ?? ""
        } catch {
            Logger.viewCycle.error("failed to get user id for message \(error)")
            return ""
        }
    }

    var body: some View {
        if includeProfileHeader {
            UI.MessageEventProfileView(event: event, actions: self, imageLoader: appState.matrixClient)
                .font(.system(size: .init(fontSize)))
        }
        UI.MessageEventBodyView(event: event, focused: isEventFocused, reactions: msg.reactions, actions: self, ownUserID: ownUserId, imageLoader: appState.matrixClient, roomMembers: timeline?.room.members ?? []) {
            VStack(alignment: .leading, spacing: 10) {
                if let replyTo = msg.inReplyTo {
                    EmbeddedMessageView(embeddedEvent: replyTo.event()) {
                        timeline?.focusEvent(id: .eventId(eventId: replyTo.eventId()))
                    }
                    .padding(.bottom, 10)
                }

                message

                if let threadSummary = msg.threadSummary {
                    MessageThreadSummary(summary: threadSummary) {
                        windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
                    }
                }
            }
        }
        .font(.system(size: .init(fontSize)))
    }
}

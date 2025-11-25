import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct ChatMessageView: View, UI.MessageEventActions {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    func toggleReaction(key: String) {
        Task {
            do {
                let _ = try await timeline.timeline?.toggleReaction(itemId: event.eventOrTransactionId, key: key)
            } catch {
                Logger.viewCycle.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    func reply() {
        Logger.viewCycle.info("Reply to event: \(event.eventOrTransactionId.id)")
        timeline.sendReplyTo = event
    }

    func replyInThread() {}

    func pin() {
        Logger.viewCycle.info("Pinning message")
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do {
                let _ = try await timeline.timeline?.pinEvent(eventId: eventId)
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
                Text("File: \(content.caption ?? "no caption") \(content.filename)").textSelection(.enabled)
            case let .gallery(content: content):
                Text("Gallery: \(content.body)").textSelection(.enabled)
            case let .notice(content: content):
                Text("Notice: \(content.body)").textSelection(.enabled)
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
        case .other(eventType: _):
            Text("Custom event").textSelection(.enabled)
        }
    }

    var isEventFocused: Bool {
        guard let focusedEventId = timeline.focusedTimelineEventId else { return false }
        return focusedEventId == event.eventOrTransactionId.id
    }

    var body: some View {
        UI.MessageEventView(event: event, focused: isEventFocused, reactions: msg.reactions, actions: self, imageLoader: appState.matrixClient) {
            VStack(alignment: .leading, spacing: 20) {
                if msg.inReplyTo != nil || (!timeline.isThreadFocus && msg.threadSummary != nil) {
                    VStack(alignment: .leading) {
                        if let replyTo = msg.inReplyTo {
                            EmbeddedMessageView(embeddedEvent: replyTo.event()) {
                                timeline.focusEvent(id: replyTo.eventId())
                            }
                        }

                        if let threadSummary = msg.threadSummary {
                            Text("Thread summary (\(threadSummary.numReplies()) messages)")
                                .italic()
                            EmbeddedMessageView(embeddedEvent: threadSummary.latestEvent()) {
                                windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
                            }
                        }
                    }
                    .foregroundStyle(.gray)
                }

                message
            }
        }
    }
}

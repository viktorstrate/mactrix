import MatrixRustSDK
import OSLog
import SwiftUI

struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @Binding var height: CGFloat?
    @AppStorage("fontSize") var fontSize: Int = 13

    @State private var isLoaded: Bool = false
    @State private var chatInput: String = ""
    @FocusState private var chatFocused: Bool

    func sendMessage() async {
        guard !chatInput.isEmpty else { return }
        guard let innerTimeline = timeline.timeline else { return }

        let msg = messageEventContentFromMarkdown(md: chatInput)

        do {
            if let replyTo {
                _ = try await innerTimeline.sendReply(msg: msg, eventId: replyTo.eventOrTransactionId.id)
            } else {
                _ = try await innerTimeline.send(msg: msg)
            }
        } catch {
            Logger.viewCycle.error("failed to send message: \(error)")
        }

        chatInput = ""
        replyTo = nil
        timeline.scrollPosition.scrollTo(edge: .bottom)
    }

    private func clearDraft() {
        Task {
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed to clear draft: \(error)")
            }
        }
    }

    private func saveDraft() {
        if chatInput.isEmpty {
            clearDraft()
            return
        }

        Task {
            let draftType: ComposerDraftType
            if let replyTo {
                draftType = .reply(eventId: replyTo.eventOrTransactionId.id)
            } else {
                draftType = .newMessage
            }
            let draft = ComposerDraft(
                plainText: chatInput,
                htmlText: nil,
                draftType: draftType,
                attachments: []
            )
            do {
                try await room.saveComposerDraft(draft: draft, threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed save draft: \(error)")
            }
        }
    }

    private func loadDraft() async -> Bool {
        do {
            guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId) else {
                // no draft to load
                return true
            }
            self.chatInput = draft.plainText
            switch draft.draftType {
            case .reply(eventId: let eventId):
                // we need a timeline to be able to populate the reply; return false so we can try again
                guard let innerTimeline = timeline.timeline else {
                    return false
                }

                do {
                    let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
                    self.timeline.sendReplyTo = item
                } catch {
                    Logger.viewCycle.error("failed to resolve reply target: \(error)")
                }
            case .newMessage, .edit:
                // nothing to do
                return true
            }
        } catch {
            Logger.viewCycle.error("failed to load draft: \(error)")
        }
        return true  // so we don't try again
    }

    private func chatInputChanged() {
        guard isLoaded else { return } // avoid working on a draft that's being restored
        if !chatInput.isEmpty {
            Task {
                try await room.typingNotice(isTyping: !chatInput.isEmpty)
            }
        }
        saveDraft()
    }

    var replyEmbeddedDetails: EmbeddedEventDetails? {
        guard let replyTo else { return nil }

        return .ready(content: replyTo.content, sender: replyTo.sender, senderProfile: replyTo.senderProfile, timestamp: replyTo.timestamp, eventOrTransactionId: replyTo.eventOrTransactionId)
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let replyEmbeddedDetails {
                EmbeddedMessageView(embeddedEvent: replyEmbeddedDetails) {
                    replyTo = nil
                }
            }
            TextField("Message room", text: $chatInput, axis: .vertical)
                .focused($chatFocused)
                .onSubmit { Task { await sendMessage() } }
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(10)
        }
        .font(.system(size: .init(fontSize)))
        .background(
            GeometryReader { proxy in
                Color(NSColor.textBackgroundColor)
                    .onChange(of: proxy.size.height) { _, inputHeight in
                        self.height = inputHeight
                    }
            }
        )
        .cornerRadius(4)
        .lineSpacing(2)
        .frame(minHeight: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        // .shadow(color: .black.opacity(0.1), radius: 4)
        .onTapGesture {
            chatFocused = true
        }
        .task(id: !chatInput.isEmpty) {
            let isTyping = !chatInput.isEmpty
            do {
                try await room.typingNotice(isTyping: isTyping)
            } catch {
                Logger.viewCycle.error("Failed to set typing notice: \(error)")
            }
        }
        .pointerStyle(.horizontalText)
        .padding([.horizontal, .bottom], 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

/* #Preview {
     ChatInputView()
 } */

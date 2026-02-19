import MatrixRustSDK
import OSLog
import SwiftUI

struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @Binding var height: CGFloat?
    @AppStorage("fontSize") var fontSize: Int = 13

    @State private var isDraftLoaded: Bool = false
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

    private func saveDraft() async {
        guard isDraftLoaded else { return } // avoid saving a draft hasn't yet been restored
        if chatInput.isEmpty && replyTo == nil {
            Logger.viewCycle.debug("clearing draft")
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed to clear draft: \(error)")
            }
            return
        }

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
            Logger.viewCycle.debug("saved draft")
        } catch {
            Logger.viewCycle.error("failed save draft: \(error)")
        }
    }

    private func loadDraft() async {
        guard !isDraftLoaded else { return }  // don't load a draft more than once
        do {
            guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId) else {
                // no draft to load
                isDraftLoaded = true
                return
            }
            self.chatInput = draft.plainText
            switch draft.draftType {
            case .reply(eventId: let eventId):
                // we need a timeline to be able to populate the reply; return false so we can try again
                guard let innerTimeline = timeline.timeline else {
                    isDraftLoaded = false
                    return
                }

                do {
                    let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
                    self.timeline.sendReplyTo = item
                } catch {
                    Logger.viewCycle.error("failed to resolve reply target: \(error)")
                }
            case .newMessage, .edit:
                // nothing to do
                isDraftLoaded = true
                return
            }
        } catch {
            Logger.viewCycle.error("failed to load draft: \(error)")
        }
        isDraftLoaded = true  // so we don't try again
    }

    private func chatInputChanged() async {
        guard isDraftLoaded else { return } // avoid working on a draft that's being restored
        if !chatInput.isEmpty {
            do {
                try await room.typingNotice(isTyping: !chatInput.isEmpty)
            } catch {
                Logger.viewCycle.warning("Failed to send typing notice: \(error)")
            }
        }
        await saveDraft()
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
                .disabled(!isDraftLoaded)  // avoid inputs until we've tried to load a draft
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
        .task(id: chatInput) {
            await chatInputChanged()
        }
        .task(id: replyTo?.eventOrTransactionId) {
            await saveDraft()
        }
        .task(id: timeline.timeline != nil) {
            // we need the timeline to be populated before we load a draft
            // (in case the draft holds a reply)
            await loadDraft()
        }
        .pointerStyle(.horizontalText)
        .padding([.horizontal, .bottom], 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

/* #Preview {
     ChatInputView()
 } */

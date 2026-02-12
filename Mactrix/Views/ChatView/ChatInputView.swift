import MatrixRustSDK
import OSLog
import SwiftUI

struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @Binding var height: CGFloat?
    @AppStorage("fontSize") var fontSize: Int = 13

    @State private var chatInput: String = ""
    @FocusState private var chatFocused: Bool

    func sendMessage() {
        guard !chatInput.isEmpty else { return }
        guard let innerTimeline = timeline.timeline else { return }

        Task {
            let msg = messageEventContentFromMarkdown(md: chatInput)

            do {
                if let replyTo {
                    let _ = try await innerTimeline.sendReply(msg: msg, eventId: replyTo.eventOrTransactionId.id)
                } else {
                    let _ = try await innerTimeline.send(msg: msg)
                }
            } catch {
                Logger.viewCycle.error("failed to send message: \(error)")
            }

            chatInput = ""
            replyTo = nil
            timeline.scrollPosition.scrollTo(edge: .bottom)
        }
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
                .onSubmit { sendMessage() }
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
                        print("Input height: \(inputHeight)")
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
        .onChange(of: !chatInput.isEmpty) { _, isTyping in
            Task {
                try await room.typingNotice(isTyping: isTyping)
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

import MatrixRustSDK
import SwiftUI

struct ChatInputView: View {
    let room: Room
    let timeline: Timeline?

    @State private var chatInput: String = ""
    @FocusState private var chatFocused: Bool

    func sendMessage() {
        guard !chatInput.isEmpty else { return }
        guard let timeline = timeline else { return }

        Task {
            let msg = messageEventContentFromMarkdown(md: chatInput)
            let _ = try await timeline.send(msg: msg)
            chatInput = ""
        }
    }

    var body: some View {
        VStack {
            TextField("Message room", text: $chatInput, axis: .vertical)
                .focused($chatFocused)
                .onSubmit { sendMessage() }
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(10)
        }
        .font(.system(size: 14))
        .background(Color(NSColor.textBackgroundColor))
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

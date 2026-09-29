import SwiftUI

public struct MessageReplyView: View {
    let username: String
    let message: String
    let action: () -> Void

    public init(username: String, message: String, action: @escaping () -> Void = {}) {
        self.username = username
        self.message = message
        self.action = action
    }

    var content: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(username)
                    .bold()
                    .textSelection(.enabled)
                Text(message.formatAsMarkdown)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            ZStack {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4).opacity(0.5).frame(width: 3)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 4)
                    .padding(.leading, 2)
                    .opacity(0.05)
            }
        )
        .italic()
    }

    public var body: some View {
        Button {
            action()
        } label: {
            content
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        MessageReplyView(username: "user@example.com", message: "This is the root message")
        Text("Real content")
    }.padding()
}

import SwiftUI
import MatrixRustSDK

struct ChatReactionView: View {
    let reaction: Reaction
    
    var body: some View {
        HStack(spacing: 0) {
            Text(reaction.key)
            Text("\(reaction.senders.count)")
                .padding(.horizontal, 6)
        }
        .padding(4)
        .background(Color.blue.quaternary)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue.tertiary)
        )
    }
}

#Preview {
    ChatReactionView(reaction: .previewReaction)
        .padding()
}

struct ChatMessageView: View {
    
    let event: EventTimelineItem
    let msg: MsgLikeContent
    
    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfile, let displayName = displayName {
            return displayName
        }
        return event.sender
    }
    
    @ViewBuilder
    var message: some View {
        switch msg.kind {
        case .message(content: let content):
            switch content.msgType {
            case .emote(content: let content):
                Text("Emote: \(content.body)")
            case .image(content: let content):
                MessageImageView(content: content)
            case .audio(content: let content):
                Text("Audio: \(content.caption ?? "no caption") \(content.filename)")
            case .video(content: let content):
                Text("Video: \(content.caption ?? "no caption") \(content.filename)")
            case .file(content: let content):
                Text("File: \(content.caption ?? "no caption") \(content.filename)")
            case .gallery(content: let content):
                Text("Gallery: \(content.body)")
            case .notice(content: let content):
                Text("Notice: \(content.body)")
            case .text(content: let content):
                Text(content.body)
            case .location(content: let content):
                Text("Location: \(content.body) \(content.geoUri)")
            case .other(msgtype: let msgtype, body: let body):
                Text("Other: \(msgtype) \(body)")
            }
        case .sticker(body: let body, info: _, source: _):
            Text("Sticker: \(body)")
        case .poll(question: let question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _, hasBeenEdited: _):
            Text("Poll: \(question)")
        case .redacted:
            Text("Message redacted")
        case .unableToDecrypt(msg: _):
            Text("Unable to decrypt")
        case .other(eventType: _):
            Text("Custom event")
        }
    }
    
    var timeFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    @State private var hoverText: Bool = false
    
    @ViewBuilder
    var hoverActions: some View {
        HStack {
            Button(action: {}) {
                Image(systemName: "face.smiling")
            }.buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "arrowshape.turn.up.left")
            }.buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "ellipsis.message")
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
        .padding(.trailing, 20)
        .padding(.top, 18)
        .opacity(hoverText ? 1 : 0)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Profile icon and name
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Circle()
                            .frame(width: 32, height: 32)
                        
                    }.frame(width: 64)
                    
                    Text(name)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                // Main body
                HStack(alignment: .top, spacing: 0) {
                    HStack {
                        Text(timeFormat.string(from: event.timestamp.date))
                            .foregroundStyle(.gray)
                            .font(.system(.footnote))
                            .padding(.trailing, 5)
                            .padding(.top, 3)
                    }
                    .frame(width: 64 - 10)
                    .opacity(hoverText ? 1 : 0)
                    message
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.tertiary)
                        .opacity(hoverText ? 1 : 0)
                )
                .padding(.horizontal, 10)
                
                // Reactions
                HStack {
                    Spacer().frame(width: 64)
                    ForEach(msg.reactions) { reaction in
                        ChatReactionView(reaction: reaction)
                    }
                    Spacer()
                }
                .padding(.top, 10)
            }
            
            hoverActions
        }
        .padding(.top, 5)
        .onHover { hover in
            hoverText = hover
        }
    }
}

#Preview {
    ChatMessageView(event: .previewTextItem, msg: .previewTextMessage)
}

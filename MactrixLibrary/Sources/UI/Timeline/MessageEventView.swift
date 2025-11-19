import Models
import SwiftUI

struct HoverButton<Icon: View>: View {
    @State private var hovering = false

    @ViewBuilder
    let icon: () -> Icon
    let tooltip: LocalizedStringKey
    let action: () -> Void

    let size: CGFloat = 24.0

    var body: some View {
        Button(action: action) {
            icon()
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .foregroundStyle(hovering ? Color.accentColor : .primary)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.quaternary)
                .frame(width: size, height: size)
                .opacity(hovering ? 1 : 0)
        )
        .frame(width: size, height: size)
        .padding(2)
        .onHover { hover in
            hovering = hover
        }
    }
}

public protocol MessageEventActions {
    func toggleReaction(key: String)
    func reply()
    func replyInThread()
    func pin()
}

struct MessageTimestampView: View {
    let date: Date
    let hover: Bool

    var timeFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        HStack {
            Text(timeFormat.string(from: date))
                .foregroundStyle(.gray)
                .font(.system(.footnote))
                .padding(.trailing, 5)
                .padding(.top, 3)
        }
        .frame(width: 64 - 10)
        // .opacity(hover ? 1 : 0)
    }
}

public struct MessageEventView<MessageView: View, EventTimelineItem: Models.EventTimelineItem, Reaction: Models.Reaction>: View {
    let event: EventTimelineItem
    let reactions: [Reaction]
    let message: MessageView
    let actions: MessageEventActions
    let imageLoader: ImageLoader?

    public init(event: EventTimelineItem, reactions: [Reaction], actions: MessageEventActions, imageLoader: ImageLoader?, @ViewBuilder message: () -> MessageView) {
        self.event = event
        self.reactions = reactions
        self.actions = actions
        self.imageLoader = imageLoader
        self.message = message()
    }

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    @State private var hoverText: Bool = false

    @ViewBuilder
    var hoverActions: some View {
        HStack(spacing: 0) {
            HoverButton(icon: { Text("👍") }, tooltip: "React") {
                actions.toggleReaction(key: "👍")
            }
            HoverButton(icon: { Text("🎉") }, tooltip: "React") {
                actions.toggleReaction(key: "🎉")
            }
            HoverButton(icon: { Text("❤️") }, tooltip: "React") {
                actions.toggleReaction(key: "❤️")
            }
            Divider().frame(height: 18)
            HoverButton(icon: { Image(systemName: "face.smiling") }, tooltip: "React") {}
            HoverButton(icon: { Image(systemName: "arrowshape.turn.up.left") }, tooltip: "Reply") {}
            HoverButton(icon: { Image(systemName: "ellipsis.message") }, tooltip: "Reply in thread") {}
            HoverButton(icon: { Image(systemName: "pin") }, tooltip: "Pin") {}
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
        .padding(.trailing, 20)
        .padding(.top, 8)
        .opacity(hoverText ? 1 : 0)
    }

    func reactionIsActive(_ reaction: Reaction) -> Bool {
        return event.isOwn && reaction.senders.contains(where: { $0.senderId == event.sender })
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Profile icon and name
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        AvatarImage(avatarUrl: event.senderProfileDetails.avatarUrl, imageLoader: imageLoader)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }.frame(width: 64)

                    Text(name)
                        .fontWeight(.bold)
                    Spacer()
                }

                // Main body
                HStack(alignment: .top, spacing: 0) {
                    MessageTimestampView(date: event.date, hover: hoverText)
                    message
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                        .opacity(hoverText ? 1 : 0)
                )
                .padding(.horizontal, 10)

                // Reactions
                HStack {
                    Spacer().frame(width: 64)
                    ForEach(reactions) { reaction in
                        MessageReactionView(
                            reaction: reaction,
                            active: Binding(
                                get: { reactionIsActive(reaction) },
                                set: { if $0 != reactionIsActive(reaction) { actions.toggleReaction(key: reaction.key) } }
                            )
                        )
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

public struct MockMessageEventActions: MessageEventActions {
    public func toggleReaction(key _: String) {}
    public func reply() {}
    public func replyInThread() {}
    public func pin() {}
}

#Preview {
    MessageEventView(
        event: MockEventTimelineItem(),
        reactions: [MockReaction()],
        actions: MockMessageEventActions(),
        imageLoader: nil
    ) {
        Text("This is the body of the message")
    }
    .padding(.vertical)
}

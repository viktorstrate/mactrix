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
    func focusUser()
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

struct MessageMainBody<MessageView: View, EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let message: MessageView
    let hover: Bool
    let focused: Bool

    var body: some View {
        // Main body
        HStack(alignment: .top, spacing: 0) {
            MessageTimestampView(date: event.date, hover: hover)
            message
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(focused ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                .opacity(hover || focused ? 1 : 0)
        )
        .padding(.horizontal, 10)
    }
}

public struct MessageEventProfileView<EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let actions: MessageEventActions
    let imageLoader: ImageLoader?

    public init(event: EventTimelineItem, actions: MessageEventActions, imageLoader: ImageLoader?) {
        self.event = event
        self.actions = actions
        self.imageLoader = imageLoader
    }

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    public var body: some View {
        // Profile icon and name
        Button(action: actions.focusUser) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    AvatarImage(userProfile: event, imageLoader: imageLoader)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }.frame(width: 64)

                Username(userProfile: event)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct MessageEventBodyView<
    MessageView: View,
    EventTimelineItem: Models.EventTimelineItem,
    Reaction: Models.Reaction,
    RoomMember: Models.RoomMember
>: View {
    let event: EventTimelineItem
    let focused: Bool
    let reactions: [Reaction]
    let message: MessageView
    let actions: MessageEventActions
    let imageLoader: ImageLoader?
    let ownUserId: String
    let roomMembers: [RoomMember]

    public init(
        event: EventTimelineItem,
        focused: Bool,
        reactions: [Reaction],
        actions: MessageEventActions,
        ownUserID: String,
        imageLoader: ImageLoader?,
        roomMembers: [RoomMember],
        @ViewBuilder message: () -> MessageView
    ) {
        self.event = event
        self.focused = focused
        self.reactions = reactions
        self.actions = actions
        self.ownUserId = ownUserID
        self.imageLoader = imageLoader
        self.roomMembers = roomMembers
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

            if event.canBeRepliedTo {
                HoverButton(icon: { Image(systemName: "arrowshape.turn.up.left") }, tooltip: "Reply") {
                    actions.reply()
                }

                HoverButton(icon: { Image(systemName: "ellipsis.message") }, tooltip: "Reply in thread") {
                    actions.replyInThread()
                }
            }

            HoverButton(icon: { Image(systemName: "pin") }, tooltip: "Pin") {
                actions.pin()
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
        .padding(.trailing, 20)
        .padding(.top, -30)
        .opacity(hoverText ? 1 : 0)
    }

    func reactionIsActive(_ reaction: Reaction) -> Bool {
        return reaction.senders.contains(where: { $0.senderId == ownUserId })
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                MessageMainBody(
                    event: event,
                    message: message,
                    hover: hoverText,
                    focused: focused
                )

                // Reactions
                if !reactions.isEmpty {
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
                        ReadReciptsView(receipts: event.userReadReceipts, imageLoader: imageLoader, roomMembers: roomMembers)
                            .padding(.horizontal, 10)
                    }
                    .padding(.top, 10)
                } else if !event.userReadReceipts.isEmpty {
                    HStack {
                        Spacer()
                        ReadReciptsView(receipts: event.userReadReceipts, imageLoader: imageLoader, roomMembers: roomMembers)
                            .padding(.horizontal, 10)
                    }.padding(.top, 10)
                }
            }

            hoverActions
        }
        .onHover { hover in
            hoverText = hover
        }
        .padding(.bottom, reactions.isEmpty ? 0 : 10)
    }
}

public struct MockMessageEventActions: MessageEventActions {
    public func toggleReaction(key _: String) {}
    public func reply() {}
    public func replyInThread() {}
    public func pin() {}
    public func focusUser() {}
}

#Preview {
    VStack(spacing: 0) {
        MessageEventProfileView(event: MockEventTimelineItem(), actions: MockMessageEventActions(), imageLoader: nil)

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction](),
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("This is the body of the message")
        }

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction()],
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("This is another message from the same sender, this message is long enough that it will wrap to the next line".formatAsMarkdown)
        }

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction()],
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("Yet another message")
        }
    }
}

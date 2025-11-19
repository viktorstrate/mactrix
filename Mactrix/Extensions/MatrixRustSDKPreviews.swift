import Foundation
import MatrixRustSDK

public extension MsgLikeContent {
    static var previewTextMessage: MsgLikeContent {
        MsgLikeContent(kind: .message(content: .previewTextMessage), reactions: [.previewReaction], inReplyTo: nil, threadRoot: nil, threadSummary: nil)
    }
}

public extension MessageContent {
    static var previewTextMessage: MessageContent {
        MessageContent(msgType: .text(content: TextMessageContent(body: "Hello world", formatted: nil)), body: "Hello world", isEdited: false, mentions: nil)
    }
}

public extension Reaction {
    static var previewReaction: Reaction {
        Reaction(key: "😊", senders: [ReactionSenderData(senderId: "user1", timestamp: .previewTimestamp)])
    }
}

public extension Timestamp {
    static var previewTimestamp: Timestamp {
        Timestamp(Date.now.timeIntervalSince1970)
    }
}

public extension EventTimelineItem {
    static var previewTextItem: EventTimelineItem {
        EventTimelineItem(isRemote: false, eventOrTransactionId: .eventId(eventId: "123"), sender: "Sender Name", senderProfile: .unavailable, isOwn: true, isEditable: false, content: .msgLike(content: .previewTextMessage), timestamp: .previewTimestamp, localSendState: nil, localCreatedAt: nil, readReceipts: [:], origin: nil, canBeRepliedTo: true, lazyProvider: LazyTimelineItemProvider(noPointer: .init()))
    }
}

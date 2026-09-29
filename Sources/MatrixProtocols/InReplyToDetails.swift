import Foundation

public enum EventOrTransactionId {
    case eventId(eventId: String)
    case transactionId(transactionId: String)
}

public enum TimelineItemContent<MsgContent: MsgLikeContent> {
    case msgLike(content: MsgContent)
    case callInvite
    case rtcNotification
    case roomMembership(userId: String, userDisplayName: String?, change: Void /* MembershipChange? */, reason: String?)
    case profileChange(displayName: String?, prevDisplayName: String?, avatarUrl: String?, prevAvatarUrl: String?)
    case state(stateKey: String, content: Void /* OtherState */ )
    case failedToParseMessageLike(eventType: String, error: String)
    case failedToParseState(eventType: String, stateKey: String, error: String)
}

public enum EmbeddedEventDetails<MsgContent: MsgLikeContent> {
    case unavailable
    case pending
    case ready(content: TimelineItemContent<MsgContent>, sender: String, senderProfile: ProfileDetails, date: Date, eventOrTransactionId: EventOrTransactionId)
    case error(message: String)
}

public protocol InReplyToDetailsProtocol {
    associatedtype MsgContent: MsgLikeContent

    var event: EmbeddedEventDetails<MsgContent> { get }

    var eventId: String { get }
}

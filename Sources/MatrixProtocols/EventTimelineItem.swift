import Foundation

public enum ProfileDetails {
    case unavailable
    case pending
    case ready(displayName: String?, displayNameAmbiguous: Bool, avatarUrl: String?)
    case error(message: String)

    public var avatarUrl: String? {
        if case let .ready(displayName: _, displayNameAmbiguous: _, avatarUrl: avatarUrl) = self {
            return avatarUrl
        }
        return nil
    }
}

public struct Receipt: Equatable, Hashable {
    public var timestamp: Date?

    public init(timestamp: Date?) {
        self.timestamp = timestamp
    }
}

public protocol EventTimelineItem: UserProfile {
    var isRemote: Bool { get }
    // var eventOrTransactionId: EventOrTransactionId { get }
    var sender: String { get }
    var senderProfileDetails: ProfileDetails { get }
    var isOwn: Bool { get }
    var isEditable: Bool { get }
    // var content: TimelineItemContent { get }
    var date: Date { get }
    // var localSendState: EventSendState? { get }
    var localCreatedAt: UInt64? { get }
    var userReadReceipts: [String: Receipt] { get }
    // var origin: EventItemOrigin? { get }
    var canBeRepliedTo: Bool { get }
    // var lazyProvider: LazyTimelineItemProvider { get }
}

public struct MockEventTimelineItem: EventTimelineItem {
    public init() {}

    public var isRemote: Bool {
        true
    }

    public var sender: String {
        "sender@address"
    }

    public var senderProfileDetails: ProfileDetails {
        .ready(displayName: "Sender Name", displayNameAmbiguous: false, avatarUrl: nil)
    }

    public var isOwn: Bool {
        false
    }

    public var isEditable: Bool {
        false
    }

    public var date: Date {
        .now
    }

    public var localCreatedAt: UInt64? {
        nil
    }

    public var userReadReceipts: [String: Receipt] {
        [
            "foo@matrix.org": .init(timestamp: .now),
            "bar@matrix.org": .init(timestamp: .now + 2)
        ]
    }

    public var canBeRepliedTo: Bool {
        true
    }

    public var userId: String { sender }
    public var displayName: String? { nil }
    public var avatarUrl: String? { nil }
}

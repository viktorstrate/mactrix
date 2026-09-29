import Foundation

public protocol Reaction: Identifiable {
    associatedtype SenderData: ReactionSenderData

    var key: String { get }
    var senders: [SenderData] { get }
}

public protocol ReactionSenderData {
    var senderId: String { get }
    var date: Date { get }
}

public struct MockReactionSenderData: ReactionSenderData {
    public var senderId: String {
        "sender@address"
    }

    public var date: Date {
        .now
    }
}

public struct MockReaction: Reaction {
    public init() {}

    public var senders: [MockReactionSenderData] {
        [MockReactionSenderData()]
    }

    public typealias SenderData = MockReactionSenderData

    public var key: String {
        "😄"
    }

    public var id: String {
        key
    }
}

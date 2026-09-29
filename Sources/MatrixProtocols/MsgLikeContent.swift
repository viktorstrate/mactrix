import Foundation

public protocol Mentions {
    var userIds: [String] { get }
    var room: Bool { get }
}

public protocol MessageContent {
    //var msgType: MessageType { get }
    var body: String { get }
    var isEdited: Bool { get }
    var mentions: Mentions? { get }
}

public enum MsgLikeKind {
    /**
     * An `m.room.message` event or extensible event, including edits.
     */
    case message(content: MessageContent)
    /**
     * An `m.sticker` event.
     */
    case sticker(body: String, info: Void /* ImageInfo */, source: Void /* MediaSource */ )
    /**
     * An `m.poll.start` event.
     */
    case poll(question: String, kind: Void /* PollKind */, maxSelections: UInt64, answers: Void /* [PollAnswer] */, votes: [String: [String]], endTime: Date?, hasBeenEdited: Bool)
    /**
     * A redacted message.
     */
    case redacted
    /**
     * An `m.room.encrypted` event that could not be decrypted.
     */
    case unableToDecrypt(msg: Void /* EncryptedMessage */ )
    /**
     * A custom message like event.
     */
    case other(eventType: Void /* MessageLikeEventType */ )
}

public protocol MsgLikeContent {
    associatedtype MsgReaction: Reaction

    var kind: MsgLikeKind { get }
    var reactions: [MsgReaction] { get }
    /**
     * The event this message is replying to, if any.
     */
    // var inReplyTo: InReplyToDetails? { get }
    /**
     * Event ID of the thread root, if this is a message in a thread.
     */
    var threadRoot: String? { get }
    /**
     * Details about the thread this message is the root of.
     */
    // var threadSummary: ThreadSummary? { get }
}

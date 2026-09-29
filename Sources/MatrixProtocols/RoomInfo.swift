import Foundation

public protocol RoomInfo {
    var id: String { get }
    // var encryptionState: EncryptionState { get }
    var creators: [String]? { get }
    /**
     * The room's name from the room state event if received from sync, or one
     * that's been computed otherwise.
     */
    var displayName: String? { get }
    /**
     * Room name as defined by the room state event only.
     */
    var rawName: String? { get }
    var topic: String? { get }
    var avatarUrl: String? { get }
    var isDirect: Bool { get }
    /**
     * Whether the room is public or not, based on the join rules.
     *
     * Can be `None` if the join rules state event is not available for this
     * room.
     */
    var isPublic: Bool? { get }
    var isSpace: Bool { get }
    /**
     * If present, it means the room has been archived/upgraded.
     */
    // var successorRoom: SuccessorRoom? { get }
    var isFavourite: Bool { get }
    var canonicalAlias: String? { get }
    var alternativeAliases: [String] { get }
    // var membership: Membership { get }
    /**
     * Member who invited the current user to a room that's in the invited
     * state.
     *
     * Can be missing if the room membership invite event is missing from the
     * store.
     */
    // var inviter: RoomMember? { get }
    // var heroes: [RoomHero] { get }
    var activeMembersCount: UInt64 { get }
    var invitedMembersCount: UInt64 { get }
    var joinedMembersCount: UInt64 { get }
    var highlightCount: UInt64 { get }
    var notificationCount: UInt64 { get }
    // var cachedUserDefinedNotificationMode: RoomNotificationMode? { get }
    var hasRoomCall: Bool { get }
    var activeRoomCallParticipants: [String] { get }
    /**
     * Whether this room has been explicitly marked as unread
     */
    var isMarkedUnread: Bool { get }
    /**
     * "Interesting" messages received in that room, independently of the
     * notification settings.
     */
    var numUnreadMessages: UInt64 { get }
    /**
     * Events that will notify the user, according to their
     * notification settings.
     */
    var numUnreadNotifications: UInt64 { get }
    /**
     * Events causing mentions/highlights for the user, according to their
     * notification settings.
     */
    var numUnreadMentions: UInt64 { get }
    /**
     * The currently pinned event ids.
     */
    var pinnedEventIds: [String] { get }
    /**
     * The join rule for this room, if known.
     */
    // var joinRule: JoinRule? { get }
    /**
     * The history visibility for this room, if known.
     */
    // var historyVisibility: RoomHistoryVisibility { get }
    /**
     * This room's current power levels.
     *
     * Can be missing if the room power levels event is missing from the store.
     */
    // var powerLevels: RoomPowerLevels? { get }
    /**
     * This room's version.
     */
    var roomVersion: String? { get }
    /**
     * Whether creators are privileged over every other user (have infinite
     * power level).
     */
    var privilegedCreatorsRole: Bool { get }
}

public struct MockRoomInfo: RoomInfo {
    public init() {}

    public var id: String { "mock_id" }

    public var creators: [String]? { nil }

    public var displayName: String? { "Room Name" }

    public var rawName: String? { "room_name_raw" }

    public var topic: String? { "The topic of the room" }

    public var avatarUrl: String? { nil }

    public var isDirect: Bool { false }

    public var isPublic: Bool? { true }

    public var isSpace: Bool { false }

    public var isFavourite: Bool { false }

    public var canonicalAlias: String? { "#room:matrix.org" }

    public var alternativeAliases: [String] { [] }

    public var activeMembersCount: UInt64 { 3 }

    public var invitedMembersCount: UInt64 { 1 }

    public var joinedMembersCount: UInt64 { 8 }

    public var highlightCount: UInt64 { 0 }

    public var notificationCount: UInt64 { 2 }

    public var hasRoomCall: Bool { false }

    public var activeRoomCallParticipants: [String] { [] }

    public var isMarkedUnread: Bool { false }

    public var numUnreadMessages: UInt64 { 4 }

    public var numUnreadNotifications: UInt64 { 2 }

    public var numUnreadMentions: UInt64 { 2 }

    public var pinnedEventIds: [String] { [] }

    public var roomVersion: String? { "12" }

    public var privilegedCreatorsRole: Bool { false }
}

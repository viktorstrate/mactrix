import Foundation

/**
 * The rule used for users wishing to join this room.
 */

public enum JoinRule {
    /**
     * Anyone can join the room without any prior action.
     */
    case `public`
    /**
     * A user who wishes to join the room must first receive an invite to the
     * room from someone already inside of the room.
     */
    case invite
    /**
     * Users can join the room if they are invited, or they can request an
     * invite to the room.
     *
     * They can be allowed (invited) or denied (kicked/banned) access.
     */
    case knock

    case other
}

/**
 * The preview of a room, be it invited/joined/left, or not.
 */
public protocol RoomPreviewInfo {
    /**
     * The room id for this room.
     */
    var roomId: String { get }
    /**
     * The canonical alias for the room.
     */
    var canonicalAlias: String? { get }
    /**
     * The room's name, if set.
     */
    var name: String? { get }
    /**
     * The room's topic, if set.
     */
    var topic: String? { get }
    /**
     * The MXC URI to the room's avatar, if set.
     */
    var avatarUrl: String? { get }
    /**
     * The number of joined members.
     */
    var numJoinedMembers: UInt64 { get }
    /**
     * The number of active members, if known (joined + invited).
     */
    var numActiveMembers: UInt64? { get }
    /**
     * The room type (space, custom) or nothing, if it's a regular room.
     */
    var roomKind: RoomKind { get }
    /**
     * Is the history world-readable for this room?
     */
    var isHistoryWorldReadable: Bool? { get }
    /**
     * The membership state for the current user, if known.
     */
    var userMembership: Membership? { get }
    
    /**
     * The join rule for this room (private, public, knock, etc.).
     */
    var joinRuleInfo: JoinRule? { get }
    /**
     * Whether the room is direct or not, if known.
     */
    var isDirect: Bool? { get }
    /**
     * Room heroes.
     */
    // var heroes: [RoomHero]? { get }
}

public struct MockRoomPreviewInfo: RoomPreviewInfo {
    public init() {}
    
    public var userMembership: Membership? {
        nil
    }
    
    public var joinRuleInfo: JoinRule? {
        .public
    }
    
    public var roomKind: RoomKind {
        .room
    }
    
    public var roomId: String {
        "roomId"
    }
    
    public var canonicalAlias: String? {
        "#room:matrix.org"
    }
    
    public var name: String? {
        "Room Name"
    }
    
    public var topic: String? {
        "The topic of the **room** being previewed"
    }
    
    public var avatarUrl: String? {
        nil
    }
    
    public var numJoinedMembers: UInt64 {
        22
    }
    
    public var numActiveMembers: UInt64? {
        4
    }
    
    public var isHistoryWorldReadable: Bool? {
        true
    }
    
    public var isDirect: Bool? {
        false
    }
}

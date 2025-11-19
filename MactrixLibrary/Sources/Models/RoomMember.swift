import Foundation

public enum RoomMemberRole {
    /**
     * The member is a creator.
     *
     * A creator has an infinite power level and cannot be demoted, so this
     * role is immutable. A room can have several creators.
     */
    case creator
    /**
     * The member is an administrator.
     */
    case administrator
    /**
     * The member is a moderator.
     */
    case moderator
    /**
     * The member is a regular user.
     */
    case user
}

public protocol RoomMember: Identifiable, UserProfile {
    var userId: String { get }
    var displayName: String? { get }
    var avatarUrl: String? { get }
    // var membership: MembershipState { get }
    var isNameAmbiguous: Bool { get }
    // var powerLevel: PowerLevel { get }
    var isIgnored: Bool { get }
    var roleForPowerLevel: RoomMemberRole { get }
    var membershipChangeReason: String? { get }
}

public struct MockRoomMember: RoomMember {
    public init() {}

    public var id: String {
        userId
    }

    public var userId: String {
        "user@id"
    }

    public var displayName: String? {
        "User Name"
    }

    public var avatarUrl: String? {
        nil
    }

    public var isNameAmbiguous: Bool {
        false
    }

    public var isIgnored: Bool {
        false
    }

    public var roleForPowerLevel: RoomMemberRole {
        .user
    }

    public var membershipChangeReason: String? {
        nil
    }
}

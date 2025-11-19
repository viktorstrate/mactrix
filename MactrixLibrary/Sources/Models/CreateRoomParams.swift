import Foundation

public enum RoomAccess: Hashable {
    case publicRoom, privateRoom
}

public enum RoomVisibility {
    case published, unpublished
}

public struct CreateRoomParams {
    public var name: String
    public var topic: String
    public var enableEncryption: Bool
    // public var isDirect: Bool
    public var access: RoomAccess
    public var visibility: RoomVisibility
    // public var invite: [String]?
    // public var avatar: String?
    // public var powerLevelContentOverride: PowerLevels?
    // public var joinRuleOverride: JoinRule?
    // public var historyVisibilityOverride: RoomHistoryVisibility?
    // public var canonicalAlias: String?

    public init(name: String, topic: String, enableEncryption: Bool, access: RoomAccess, visibility: RoomVisibility) {
        self.name = name
        self.topic = topic
        self.enableEncryption = enableEncryption
        self.access = access
        self.visibility = visibility
    }

    public init() {
        name = ""
        topic = ""
        enableEncryption = false
        access = .privateRoom
        visibility = .unpublished
    }
}

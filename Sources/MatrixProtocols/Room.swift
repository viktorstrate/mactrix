import Foundation

public enum SelectedRoom<R: Room, RP: RoomPreview> {
    case joinedRoom(_ room: R)
    case previewRoom(_ room: RP)
}

public protocol RoomPreview: Hashable, Identifiable {}

public protocol Room: Hashable, Identifiable {
    var displayName: String? { get }
    var topic: String? { get }
    var encryptionState: EncryptionState { get }
}

public enum Membership {
    case invited
    case joined
    case left
    case knocked
    case banned
}

public enum RoomKind {
    /**
     * It's a plain chat room.
     */
    case room
    /**
     * It's a space that can group several rooms.
     */
    case space
    /**
     * It's a custom implementation.
     */
    case custom(value: String
    )
}

public struct MockRoom: Room, Identifiable {
    public let id: String

    public let displayName: String?
    public let topic: String?
    public let encryptionState: EncryptionState

    public static var previewRoom: MockRoom {
        let topic = """
        The topic of the room!

        The topic can span multiple lines like this.
        It also supports markdown for **bold** and _italic_ text.
        """
        return MockRoom(id: UUID().uuidString, displayName: "Test Room", topic: topic, encryptionState: .encrypted)
    }
}

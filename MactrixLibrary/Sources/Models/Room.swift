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

    @MainActor func syncMembers() async throws
}

public struct MockRoom: Room, Identifiable {
    public func syncMembers() async throws {}

    public let id: String

    public let displayName: String?
    public let topic: String?
    public let encryptionState: EncryptionState

    public static var previewRoom: MockRoom {
        return MockRoom(id: UUID().uuidString, displayName: "Test Room", topic: "The topic of the room", encryptionState: .encrypted)
    }
}

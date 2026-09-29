import Foundation

public protocol UserProfile: Identifiable {
    var userId: String { get }
    var displayName: String? { get }
    var avatarUrl: String? { get }
}

public extension UserProfile {
    var id: String { userId }
}

public struct MockUserProfile: UserProfile {
    public init() {}

    public var userId: String {
        "@user:matrix.org"
    }

    public var displayName: String? {
        "Matrix User"
    }

    public var avatarUrl: String? { nil }
}

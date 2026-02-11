import Foundation

public protocol UserProfile: Identifiable {
    var userId: String { get }
    var displayName: String? { get }
    var avatarUrl: String? { get }
}

public struct SimpleUserProfile: UserProfile {
    public var userId: String
    public var displayName: String?
    public var avatarUrl: String?
    
    public init(userId: String, profileDetails: ProfileDetails) {
        self.userId = userId
        
        switch profileDetails {
        case let .ready(displayName: displayName, displayNameAmbiguous: _, avatarUrl: avatarUrl):
            self.displayName = displayName
            self.avatarUrl = avatarUrl
        default:
            self.displayName = nil
            self.avatarUrl = nil
        }
    }
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

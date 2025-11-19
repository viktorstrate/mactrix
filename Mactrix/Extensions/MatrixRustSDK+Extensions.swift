import Foundation
import MatrixRustSDK
import Models

extension MatrixRustSDK.RoomMember: @retroactive Identifiable, Models.RoomMember {
    public var id: String {
        userId
    }

    public var roleForPowerLevel: Models.RoomMemberRole {
        suggestedRoleForPowerLevel.asModel
    }
}

extension MatrixRustSDK.RoomMemberRole {
    var asModel: Models.RoomMemberRole {
        switch self {
        case .creator:
            return .creator
        case .administrator:
            return .administrator
        case .moderator:
            return .moderator
        case .user:
            return .user
        }
    }
}

extension MatrixRustSDK.EncryptionState {
    var asModel: Models.EncryptionState {
        switch self {
        case .notEncrypted:
            return .notEncrypted
        case .encrypted:
            return .encrypted
        case .unknown:
            return .unknown
        }
    }
}

extension MatrixRustSDK.Room: @retroactive Equatable, @retroactive Hashable {
    public static func == (lhs: MatrixRustSDK.Room, rhs: MatrixRustSDK.Room) -> Bool {
        return lhs.id() == rhs.id()
    }

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(id())
    }
}

extension MatrixRustSDK.Room: @retroactive Identifiable {
    public var id: String {
        self.id()
    }
}

extension MatrixRustSDK.RoomInfo: Models.RoomInfo {}

extension MatrixRustSDK.TimelineItem: @retroactive Hashable, @retroactive Identifiable {
    public var id: String {
        uniqueId().id
    }

    public static func == (lhs: MatrixRustSDK.TimelineItem, rhs: MatrixRustSDK.TimelineItem) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension MatrixRustSDK.Reaction: @retroactive Identifiable {
    public var id: String {
        key
    }
}

extension MatrixRustSDK.Reaction: Models.Reaction {
    public typealias SenderData = MatrixRustSDK.ReactionSenderData
}

extension MatrixRustSDK.ReactionSenderData: Models.ReactionSenderData {
    public var date: Date {
        timestamp.date
    }
}

public extension MatrixRustSDK.Timestamp {
    var date: Date {
        Date(timeIntervalSince1970: Double(self) / 1000)
    }
}

extension MatrixRustSDK.VirtualTimelineItem {
    var asModel: Models.VirtualTimelineItem {
        switch self {
        case let .dateDivider(ts: ts):
            return .dateDivider(date: ts.date)
        case .readMarker:
            return .readMarker
        case .timelineStart:
            return .timelineStart
        }
    }
}

extension MatrixRustSDK.ProfileDetails {
    var asModel: Models.ProfileDetails {
        switch self {
        case .unavailable:
            return .unavailable
        case .pending:
            return .pending
        case let .ready(displayName, displayNameAmbiguous, avatarUrl):
            return .ready(displayName: displayName, displayNameAmbiguous: displayNameAmbiguous, avatarUrl: avatarUrl)
        case let .error(message):
            return .error(message: message)
        }
    }
}

extension MatrixRustSDK.EventTimelineItem: Models.EventTimelineItem {
    public var senderProfileDetails: Models.ProfileDetails {
        senderProfile.asModel
    }

    public var date: Date {
        timestamp.date
    }
}

extension MatrixRustSDK.SpaceRoom: @retroactive Identifiable {
    public var id: String {
        roomId
    }
}

extension MatrixRustSDK.UserProfile: @retroactive Identifiable, Models.UserProfile {
    public var id: String { userId }
}

extension MatrixRustSDK.SessionVerificationEmoji: @retroactive Identifiable {
    public var id: String { description() }
}

extension MatrixRustSDK.SessionVerificationEmoji: Models.SessionVerificationEmoji {
    public var description: String {
        self.description()
    }

    public var symbol: String {
        self.symbol()
    }
}

extension MatrixRustSDK.SessionVerificationData {
    var asModel: Models.SessionVerificationData<MatrixRustSDK.SessionVerificationEmoji> {
        switch self {
        case let .emojis(emojis, indices):
            return .emojis(emojis: emojis, indices: indices)
        case let .decimals(values):
            return .decimals(values: values)
        }
    }
}

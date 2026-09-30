import Foundation
import MatrixProtocols
import MatrixRustSDK

extension MatrixRustSDK.RoomMember: MatrixProtocols.UserProfile {}

extension MatrixRustSDK.RoomMember: @retroactive Identifiable, MatrixProtocols.RoomMember {
  public var id: String {
    userId
  }

  public var roleForPowerLevel: MatrixProtocols.RoomMemberRole {
    suggestedRoleForPowerLevel.asModel
  }
}

extension MatrixRustSDK.RoomMemberRole {
  var asModel: MatrixProtocols.RoomMemberRole {
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
  var asModel: MatrixProtocols.EncryptionState {
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

extension MatrixRustSDK.RoomInfo: MatrixProtocols.RoomInfo {}

/* extension MatrixRustSDK.TimelineItem: @retroactive Hashable, @retroactive Identifiable {
     public var id: String {
         uniqueId().id
     }

     public static func == (lhs: MatrixRustSDK.TimelineItem, rhs: MatrixRustSDK.TimelineItem) -> Bool {
         return lhs.id == rhs.id
             && lhs.asEvent() == rhs.asEvent()
             && lhs.asVirtual() == rhs.asVirtual()
     }

     public func hash(into hasher: inout Hasher) {
         hasher.combine(id)
         hasher.combine(asEvent())
         hasher.combine(asVirtual())
     }
 } */

/* extension MatrixRustSDK.EventTimelineItem: @retroactive Hashable {
     public static func == (lhs: MatrixRustSDK.EventTimelineItem, rhs: MatrixRustSDK.EventTimelineItem) -> Bool {
         return lhs.isRemote == rhs.isRemote
             && lhs.eventOrTransactionId == rhs.eventOrTransactionId
             && lhs.sender == rhs.sender
             && lhs.senderProfile == rhs.senderProfile
             && lhs.isOwn == rhs.isOwn
             && lhs.isEditable == rhs.isEditable
             && lhs.content == rhs.content
             && lhs.timestamp == rhs.timestamp
             && lhs.localSendState == rhs.localSendState
             && lhs.localCreatedAt == rhs.localCreatedAt
             && lhs.readReceipts == rhs.readReceipts
             && lhs.origin == rhs.origin
             && lhs.canBeRepliedTo == rhs.canBeRepliedTo
     }

     public func hash(into hasher: inout Hasher) {
         hasher.combine(eventOrTransactionId)
         hasher.combine(sender)
         hasher.combine(senderProfile)
         hasher.combine(isOwn)
         hasher.combine(isEditable)
         hasher.combine(content)
         hasher.combine(timestamp)
         hasher.combine(localSendState)
         hasher.combine(localCreatedAt)
         hasher.combine(readReceipts)
         hasher.combine(origin)
         hasher.combine(canBeRepliedTo)
     }
 } */

/* extension MatrixRustSDK.MsgLikeContent: @retroactive Hashable {
     public static func == (lhs: MatrixRustSDK.MsgLikeContent, rhs: MatrixRustSDK.MsgLikeContent) -> Bool {
         return lhs.kind == rhs.kind
             && lhs.reactions == rhs.reactions
             && lhs.inReplyTo?.eventId() == rhs.inReplyTo?.eventId()
             && lhs.threadRoot == rhs.threadRoot
             && lhs.threadSummary?.numReplies() == rhs.threadSummary?.numReplies()
     }
 } */

extension MatrixRustSDK.Reaction: @retroactive Identifiable {
  public var id: String {
    key
  }
}

extension MatrixRustSDK.Reaction: MatrixProtocols.Reaction {
  public typealias SenderData = MatrixRustSDK.ReactionSenderData
}

extension MatrixRustSDK.ReactionSenderData: MatrixProtocols.ReactionSenderData {
  public var date: Date {
    timestamp.date
  }
}

extension MatrixRustSDK.Timestamp {
  public var date: Date {
    Date(timeIntervalSince1970: Double(self) / 1000)
  }
}

extension MatrixRustSDK.VirtualTimelineItem {
  var asModel: MatrixProtocols.VirtualTimelineItem {
    switch self {
    case .dateDivider(let ts):
      return .dateDivider(date: ts.date)
    case .readMarker:
      return .readMarker
    case .timelineStart:
      return .timelineStart
    }
  }
}

extension MatrixRustSDK.ProfileDetails {
  var asModel: MatrixProtocols.ProfileDetails {
    switch self {
    case .unavailable:
      return .unavailable
    case .pending:
      return .pending
    case .ready(let displayName, let displayNameAmbiguous, let avatarUrl, _, _):
      return .ready(
        displayName: displayName, displayNameAmbiguous: displayNameAmbiguous, avatarUrl: avatarUrl)
    case .error(let message):
      return .error(message: message)
    }
  }
}

extension MatrixRustSDK.EventTimelineItem: MatrixProtocols.EventTimelineItem {
  public var userReadReceipts: [String: MatrixProtocols.Receipt] {
    readReceipts.mapValues { MatrixProtocols.Receipt(timestamp: $0.timestamp?.date) }
  }

  public var senderProfileDetails: MatrixProtocols.ProfileDetails {
    senderProfile.asModel
  }

  public var date: Date {
    timestamp.date
  }

  public var userId: String {
    sender
  }

  public var displayName: String? {
    if case .ready(displayName: let displayName, displayNameAmbiguous: _, avatarUrl: _) =
      senderProfileDetails
    {
      return displayName
    }

    return nil
  }

  public var avatarUrl: String? {
    if case .ready(displayName: _, displayNameAmbiguous: _, avatarUrl: let avatarUrl) =
      senderProfileDetails
    {
      return avatarUrl
    }

    return nil
  }
}

extension MatrixRustSDK.EventTimelineItem: @retroactive Identifiable {
  public var id: MatrixRustSDK.EventOrTransactionId {
    eventOrTransactionId
  }
}

extension MatrixRustSDK.TimelineItemContent {
  public var userInterfaceText: String {
    switch self {
    case .callInvite:
      return "call invite"
    case .msgLike(let content):
      return content.kind.userInterfaceText
    case .rtcNotification:
      return "rtc notification"
    case .roomMembership(let userId, userDisplayName: _, let change, let reason):
      return Self.roomMembershipDescription(userId: userId, change: change, reason: reason)
    case .profileChange(let displayName, let prevDisplayName, let avatarUrl, let prevAvatarUrl):
      switch (displayName, prevDisplayName, avatarUrl, prevAvatarUrl) {
      case (.some(_), .some(_), .some(_), .some(_)):
        return "changed their display name and avatar"
      case (.some(let displayName), .some(let prevDisplayName), _, _):
        return "changed their display name from \(prevDisplayName) to \(displayName)"
      case (_, _, .some(_), .some(_)):
        return "changed their avatar"
      case _:
        return "unknown profile change"
      }
    case .state(stateKey: _, let content):
      return content.description
    case .failedToParseMessageLike(let eventType, let error):
      return "failed to parse \(eventType): \(error)"
    case .failedToParseState(let eventType, let stateKey, let error):
      return "failed to parse \(eventType) \(stateKey): \(error)"
    }
  }

  public static func roomMembershipDescription(
    userId: String, change: MembershipChange?, reason: String?
  ) -> String {
    let changeMsg =
      switch change {
      case nil:
        "unknown membership change event"
      case .some(.none):
        "room membership event was none"
      case .banned:
        "banned \(userId)"
      case .error:
        "room membership event error"
      case .joined:
        "joined room"
      case .left:
        "left the room"
      case .unbanned:
        "unbanned \(userId)"
      case .kicked:
        "kicked \(userId)"
      case .invited:
        "invited \(userId)"
      case .kickedAndBanned:
        "kicked and banned \(userId)"
      case .invitationAccepted:
        "accepted invitiation to join the room"
      case .invitationRejected:
        "rejected invitiation to join the room"
      case .invitationRevoked:
        "revoked invitiation for \(userId) to join the room"
      case .knocked:
        "requested to join the room"
      case .knockAccepted:
        "accepted join request from \(userId)"
      case .knockRetracted:
        "request to join the room was retracted"
      case .knockDenied:
        "denied join request from \(userId)"
      case .notImplemented:
        "room membership event not implemented"
      }

    return if let reason {
      "\(changeMsg) because \(reason)"
    } else {
      changeMsg
    }
  }
}

extension MatrixRustSDK.MsgLikeKind {
  public var userInterfaceText: String {
    switch self {
    case .message(let content):
      return content.body
    case .sticker(let body, info: _, source: _):
      return "Sticker: \(body)"
    case .poll(
      let question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _, hasBeenEdited: _):
      return "Poll: \(question)"
    case .redacted:
      return "Redacted"
    case .unableToDecrypt(msg: _):
      return "Unable to decrypt"
    case .other(let eventType):
      return "Other: \(eventType)"
    case .liveLocation(let content):
      return "Live location: \(content.description ?? "no description")"
    }
  }
}

extension MatrixRustSDK.MessageLikeEventType {
  public var userInterfaceText: String {
    switch self {
    case .callAnswer:
      "call answer"
    case .callCandidates:
      "call candidates"
    case .callHangup:
      "call hangup"
    case .callInvite:
      "call invite"
    case .rtcNotification:
      "rtc notification"
    case .keyVerificationAccept:
      "key verification accept"
    case .keyVerificationCancel:
      "key verification cancel"
    case .keyVerificationDone:
      "key verification done"
    case .keyVerificationKey:
      "key verification key"
    case .keyVerificationMac:
      "key verification mac"
    case .keyVerificationReady:
      "key verification ready"
    case .keyVerificationStart:
      "key verification start"
    case .pollEnd:
      "poll end"
    case .pollResponse:
      "poll reponse"
    case .pollStart:
      "poll start"
    case .reaction:
      "reaction"
    case .roomEncrypted:
      "room encrypted"
    case .roomMessage:
      "room message"
    case .roomRedaction:
      "room redaction"
    case .sticker:
      "sticker"
    case .unstablePollEnd:
      "unstable poll end"
    case .unstablePollResponse:
      "unstable poll response"
    case .unstablePollStart:
      "unstable poll start"
    case .audio:
      "audio"
    case .beacon:
      "beacon"
    case .callNegotiate:
      "call negotiate"
    case .callNotify:
      "call notify"
    case .callReject:
      "call reject"
    case .callSdpStreamMetadataChanged:
      "call sdp stream metadata changed"
    case .callSelectAnswer:
      "call select answer"
    case .emote:
      "emote"
    case .encrypted:
      "encrypted"
    case .file:
      "file"
    case .image:
      "image"
    case .location:
      "location"
    case .message:
      "message"
    case .rtcDecline:
      "rtc decline"
    case .video:
      "video"
    case .voice:
      "voice"
    case .custom:
      "custom"
    }
  }
}

extension MatrixRustSDK.OtherState: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .policyRuleRoom:
      return "changed policy rules for room"
    case .policyRuleServer:
      return "changed policy rules for server"
    case .policyRuleUser:
      return "changed policy rule for user"
    case .roomAvatar(url: _):
      return "changed room avatar"
    case .roomCanonicalAlias:
      return "changed room canonical alias"
    case .roomCreate:
      return "created room"
    case .roomEncryption:
      return "changed room encryption"
    case .roomGuestAccess:
      return "changed room guest access"
    case .roomHistoryVisibility:
      return "change room history visibility"
    case .roomJoinRules:
      return "changed room join rules"
    case .roomName(let name):
      return "changed room name to '\(name ?? "empty")'"
    case .roomPinnedEvents(change: _):
      return "changed room pinned events"
    case .roomPowerLevels(
      events: _, previousEvents: _, users: _, previousUsers: _, thresholds: _, previousThresholds: _
    ):
      return "changed room power levels"
    case .roomServerAcl:
      return "changed room server acl"
    case .roomThirdPartyInvite(displayName: _):
      return "changed room third party invite"
    case .roomTombstone:
      return "room tombstone"
    case .roomTopic(let topic):
      return "changed room topic to '\(topic ?? "none")'"
    case .spaceChild:
      return "changed space child"
    case .spaceParent:
      return "changed space parent"
    case .custom(let eventType):
      return "changed custom state '\(eventType)'"
    }
  }
}

extension MatrixRustSDK.EmbeddedEventDetails {
  var message: String? {
    switch self {
    case .unavailable:
      return nil
    case .pending:
      return nil
    case .ready(let content, sender: _, senderProfile: _, timestamp: _, eventOrTransactionId: _):
      return content.userInterfaceText
    case .error(let message):
      return "Error: \(message)"
    }
  }
}

extension MatrixRustSDK.ThreadSummary: MatrixProtocols.ThreadSummary {
  public var description: String? {
    latestEvent().message
  }
}

extension MatrixRustSDK.SpaceRoom: @retroactive Identifiable {
  public var id: String {
    roomId
  }
}

extension MatrixRustSDK.EventOrTransactionId: @retroactive Identifiable {
  public var id: String {
    switch self {
    case .eventId(let eventId):
      return eventId
    case .transactionId(let transactionId):
      return transactionId
    }
  }
}

extension MatrixRustSDK.UserProfile: @retroactive Identifiable, MatrixProtocols.UserProfile {
  public var id: String {
    userId
  }
}

extension MatrixRustSDK.SessionVerificationEmoji: @retroactive Identifiable {
  public var id: String {
    description()
  }
}

extension MatrixRustSDK.SessionVerificationEmoji: MatrixProtocols.SessionVerificationEmoji {
  public var description: String {
    self.description()
  }

  public var symbol: String {
    self.symbol()
  }
}

extension MatrixRustSDK.SessionVerificationData {
  public var asModel:
    MatrixProtocols.SessionVerificationData<MatrixRustSDK.SessionVerificationEmoji>
  {
    switch self {
    case .emojis(let emojis, let indices):
      return .emojis(emojis: emojis, indices: indices)
    case .decimals(let values):
      return .decimals(values: values)
    }
  }
}

extension MatrixRustSDK.PaginationStatus: @retroactive CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .idle(let hitTimelineStart):
      "idle, hitTimelineStart=\(hitTimelineStart)"
    case .paginating:
      "paginating"
    }
  }
}

extension MatrixRustSDK.Room: @retroactive CustomDebugStringConvertible {
  public var debugDescription: String {
    "room \(id())"
  }
}

extension MatrixRustSDK.RoomPreviewInfo: @retroactive CustomDebugStringConvertible {
  public var debugDescription: String {
    "preview room info: \(roomId) \(name ?? "<no name>")"
  }
}

extension MatrixRustSDK.RoomPreviewInfo: MatrixProtocols.RoomPreviewInfo {
  public var userMembership: MatrixProtocols.Membership? {
    switch membership {
    case .joined:
      return .joined
    case .invited:
      return .invited
    case .left:
      return .left
    case .knocked:
      return .knocked
    case .banned:
      return .banned
    case nil:
      return nil
    }
  }

  public var joinRuleInfo: MatrixProtocols.JoinRule? {
    switch joinRule {
    case .invite:
      return .invite
    case .knock:
      return .knock
    case .public:
      return .public
    case nil:
      return nil
    default:
      return .other
    }
  }

  public var roomKind: MatrixProtocols.RoomKind {
    switch roomType {
    case .room:
      return .room
    case .space:
      return .space
    case .custom(let value):
      return .custom(value: value)
    }
  }
}

extension MatrixRustSDK.RoomPreview: @retroactive Hashable {
  public static func == (lhs: MatrixRustSDK.RoomPreview, rhs: MatrixRustSDK.RoomPreview) -> Bool {
    lhs.info() == rhs.info()
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(info())
  }
}

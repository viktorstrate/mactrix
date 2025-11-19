import MatrixRustSDK
import SwiftUI
import UI

struct TimelineEventView: View {
    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem

    var body: some View {
        switch event.content {
        case let .msgLike(content: content):
            ChatMessageView(timeline: timeline?.timeline, event: event, msg: content)
        case .callInvite:
            UI.GenericEventView(event: event, name: "Call invite")
        case .rtcNotification:
            UI.GenericEventView(event: event, name: "Rtc notification")
        case let .roomMembership(userId: _, userDisplayName: _, change: change, reason: reason):
            let changeMsg = switch change {
            case nil:
                "unknown membership change event"
            case .some(.none):
                "room membership event was none"
            case .banned:
                "was banned from the room"
            case .error:
                "room membership event error"
            case .joined:
                "joined room"
            case .left:
                "left the room"
            case .unbanned:
                "was unbanned from the room"
            case .kicked:
                "was kicked from the room"
            case .invited:
                "was invited"
            case .kickedAndBanned:
                "was kicked and banned from the room"
            case .invitationAccepted:
                "accepted invitiation to join the room"
            case .invitationRejected:
                "rejected invitiation to join the room"
            case .invitationRevoked:
                "invitiation to join the room was revoked"
            case .knocked:
                "requested to join the room"
            case .knockAccepted:
                "request to join the room accepted"
            case .knockRetracted:
                "request to join the room was retracted"
            case .knockDenied:
                "request to join the room denied"
            case .notImplemented:
                "room membership event not implemented"
            }

            let message: String = if let reason {
                "\(changeMsg) because \(reason)"
            } else {
                changeMsg
            }

            UI.GenericEventView(event: event, name: message)
        case let .profileChange(displayName: displayName, prevDisplayName: prevDisplayName, avatarUrl: avatarUrl, prevAvatarUrl: prevAvatarUrl):
            let changeMsg = switch (displayName, prevDisplayName, avatarUrl, prevAvatarUrl) {
            case (.some(_), .some(_), .some(_), .some(_)):
                "changed their display name and avatar"
            case let (.some(displayName), .some(prevDisplayName), _, _):
                "changed their display name from \(prevDisplayName) to \(displayName)"
            case (_, _, .some(_), .some(_)):
                "changed their avatar"
            case _:
                "unknown profile change"
            }

            UI.GenericEventView(event: event, name: changeMsg)
        case let .state(stateKey: stateKey, content: content):
            StateEventView(event: event, stateKey: stateKey, state: content)
        case .failedToParseMessageLike(eventType: _, error: let error):
            UI.GenericEventView(event: event, name: "Failed to parse message: \(error)")
        case .failedToParseState(eventType: _, stateKey: _, error: let error):
            UI.GenericEventView(event: event, name: "Failed to parse state: \(error)")
        }
    }
}

struct StateEventView: View {
    let event: EventTimelineItem
    let stateKey: String
    let state: OtherState

    var stateMessage: String {
        switch state {
        case .policyRuleRoom:
            "changed policy rules for room"
        case .policyRuleServer:
            "changed policy rules for server"
        case .policyRuleUser:
            "changed policy rule for user"
        case .roomAliases:
            "changed room aliases"
        case .roomAvatar(url: _):
            "changed room avatar"
        case .roomCanonicalAlias:
            "changed room canonical alias"
        case .roomCreate:
            "created room"
        case .roomEncryption:
            "changed room encryption"
        case .roomGuestAccess:
            "changed room guest access"
        case .roomHistoryVisibility:
            "change room history visibility"
        case .roomJoinRules:
            "changed room join rules"
        case let .roomName(name: name):
            "changed room name to '\(name ?? "empty")'"
        case .roomPinnedEvents(change: _):
            "changed room pinned events"
        case .roomPowerLevels(users: _, previous: _):
            "changed room power levels"
        case .roomServerAcl:
            "changed room server acl"
        case .roomThirdPartyInvite(displayName: _):
            "changed room third party invite"
        case .roomTombstone:
            "room tombstone"
        case let .roomTopic(topic: topic):
            "changed room topic to '\(topic ?? "none")'"
        case .spaceChild:
            "changed space child"
        case .spaceParent:
            "changed space parent"
        case let .custom(eventType: eventType):
            "changed custom state '\(eventType)'"
        }
    }

    var body: some View {
        GenericEventView(event: event, name: stateMessage)
    }
}

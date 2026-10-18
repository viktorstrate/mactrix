import MatrixIntegration
import MatrixRustSDK

/// Semantic summaries are independent of row/controller state and of localized SDK descriptions.
enum StateEventSummaryFormatter {
  struct Segment: Equatable {
    let text: String
    var isName = false
  }

  struct Summary {
    let segments: [Segment]
    let omittedEventCount: Int
    var text: String { segments.map(\.text).joined() }
  }

  private enum Action: Hashable {
    case joined, left, invited, banned, unbanned, kicked, kickedAndBanned
    case invitationAccepted, invitationRejected, invitationRevoked
    case knocked, knockAccepted, knockRetracted, knockDenied
    case displayName, avatar, displayNameAndAvatar
    case setting(Setting)
  }

  private enum Setting: String, Hashable {
    case avatar, canonicalAlias, create, encryption, guestAccess, historyVisibility
    case joinRules, name, pinnedEvents, powerLevels, serverAcl, thirdPartyInvite
    case tombstone, topic, spaceChild, spaceParent

    var phrase: String {
      switch self {
      case .avatar: "changed room avatar"
      case .canonicalAlias: "changed room canonical alias"
      case .create: "created room"
      case .encryption: "changed room encryption"
      case .guestAccess: "changed room guest access"
      case .historyVisibility: "changed room history visibility"
      case .joinRules: "changed room join rules"
      case .name: "changed room name"
      case .pinnedEvents: "changed room pinned events"
      case .powerLevels: "changed room power levels"
      case .serverAcl: "changed room server ACL"
      case .thirdPartyInvite: "changed room third party invite"
      case .tombstone: "replaced the room"
      case .topic: "changed room topic"
      case .spaceChild: "changed space child"
      case .spaceParent: "changed space parent"
      }
    }

    var isImportant: Bool {
      switch self {
      case .encryption, .guestAccess, .historyVisibility, .joinRules, .powerLevels, .serverAcl,
        .tombstone:
        true
      default: false
      }
    }
  }

  private struct Key: Hashable {
    let action: Action
    var actor: String? = nil
    var target: String? = nil
    var reason: String? = nil
    var stateKey: String? = nil
  }

  private struct Descriptor {
    let key: Key
    let phrase: String
    var targetID: String? = nil
    var targetName: String? = nil
    var actorName: String? = nil
    var targetSuffix: String = ""
    var isImportant = false
  }

  private struct Participant {
    let id: String
    let name: String
    let firstIndex: Int
    var count = 1
  }

  private struct Group {
    let descriptor: Descriptor
    var participants: [Participant]
  }

  private struct Clause {
    let segments: [Segment]
    let eventCount: Int
    let firstIndex: Int
    let isImportant: Bool
    var text: String { segments.map(\.text).joined() }
  }

  static func summary(for events: [EventTimelineItem], characterBudget: Int = 180) -> Summary {
    var groups: [Group] = []
    var groupIndices: [Key: Int] = [:]
    var clauses: [Clause] = []
    for (index, event) in events.enumerated() {
      let name = senderName(event)
      guard let descriptor = describe(event) else {
        // Unknown and unparseable content must never acquire meaning through aggregation.
        clauses.append(
          Clause(
            segments: [
              Segment(text: name, isName: true),
              Segment(text: " " + event.content.userInterfaceText),
            ],
            eventCount: 1, firstIndex: index, isImportant: isPolicyRule(event.content)))
        continue
      }
      let groupIndex: Int
      if let existing = groupIndices[descriptor.key] {
        groupIndex = existing
      } else {
        groupIndex = groups.count
        groupIndices[descriptor.key] = groupIndex
        groups.append(Group(descriptor: descriptor, participants: []))
      }
      let participantID = descriptor.targetID ?? event.sender
      let participantName =
        descriptor.targetID == nil ? name : (descriptor.targetName ?? participantID)
      if let participantIndex = groups[groupIndex].participants.firstIndex(where: {
        $0.id == participantID
      }) {
        groups[groupIndex].participants[participantIndex].count += 1
      } else {
        groups[groupIndex].participants.append(
          Participant(id: participantID, name: participantName, firstIndex: index))
      }
    }

    for group in groups {
      // Repeat counts belong to individuals, never to a combined set of users.
      let singles = group.participants.filter { $0.count == 1 }
      if !singles.isEmpty {
        clauses.append(clause(for: singles, descriptor: group.descriptor))
      }
      for participant in group.participants where participant.count > 1 {
        clauses.append(clause(for: [participant], descriptor: group.descriptor))
      }
    }
    clauses.sort { $0.firstIndex < $1.firstIndex }
    guard !clauses.isEmpty else { return Summary(segments: [], omittedEventCount: 0) }

    func render(_ selected: [Clause]) -> Summary {
      let ordered = selected.sorted { $0.firstIndex < $1.firstIndex }
      let omitted = events.count - ordered.reduce(0) { $0 + $1.eventCount }
      var members = ordered.map(\.segments)
      if omitted > 0 {
        members.append([Segment(text: "\(omitted) other \(omitted == 1 ? "event" : "events")")])
      }
      var segments: [Segment] = []
      for (index, member) in members.enumerated() {
        if index > 0 {
          segments.append(Segment(text: ", "))
        }
        segments += member
      }
      return Summary(segments: segments, omittedEventCount: omitted)
    }

    let full = render(clauses)
    if full.text.count <= characterBudget { return full }

    // Prefer security/moderation, then source order; always keep at least one complete clause.
    let candidates = clauses.filter(\.isImportant) + clauses.filter { !$0.isImportant }
    var selected: [Clause] = []
    for clause in candidates {
      if render(selected + [clause]).text.count <= characterBudget {
        selected.append(clause)
      }
    }
    if selected.isEmpty { selected = [candidates[0]] }
    return render(selected)
  }

  private static func clause(for participants: [Participant], descriptor: Descriptor) -> Clause {
    var segments: [Segment]
    if let actor = descriptor.actorName {
      segments = [Segment(text: actor, isName: true), Segment(text: " " + descriptor.phrase + " ")]
      segments += participantSegments(participants)
    } else {
      segments = participantSegments(participants)
      segments.append(Segment(text: " " + descriptor.phrase))
      if let target = descriptor.targetName {
        segments += [Segment(text: " "), Segment(text: target, isName: true)]
        if !descriptor.targetSuffix.isEmpty {
          segments.append(Segment(text: descriptor.targetSuffix))
        }
      }
    }
    if let reason = descriptor.key.reason { segments.append(Segment(text: " because " + reason)) }
    let count = participants.reduce(0) { $0 + $1.count }
    if participants.count == 1 && count > 1 {
      segments.append(Segment(text: " \(count) times"))
    }
    return Clause(
      segments: segments, eventCount: count, firstIndex: participants[0].firstIndex,
      isImportant: descriptor.isImportant)
  }

  private static func participantSegments(_ participants: [Participant]) -> [Segment] {
    var segments = [Segment(text: participants[0].name, isName: true)]
    if participants.count == 2 {
      segments += [Segment(text: " and "), Segment(text: participants[1].name, isName: true)]
    } else if participants.count > 2 {
      segments.append(Segment(text: " and \(participants.count - 1) others"))
    }
    return segments
  }

  private static func senderName(_ event: EventTimelineItem) -> String {
    if let name = event.displayName, !name.isEmpty { return name }
    return event.sender
  }

  private static func describe(_ event: EventTimelineItem) -> Descriptor? {
    switch event.content {
    case .profileChange(let name, let previousName, let avatar, let previousAvatar):
      let nameChanged = name != previousName
      let avatarChanged = avatar != previousAvatar
      switch (nameChanged, avatarChanged) {
      case (true, true):
        return Descriptor(
          key: Key(action: .displayNameAndAvatar), phrase: "changed their display name and avatar")
      case (true, false):
        return Descriptor(key: Key(action: .displayName), phrase: "changed their display name")
      case (false, true):
        return Descriptor(key: Key(action: .avatar), phrase: "changed their avatar")
      case (false, false): return nil
      }
    case .roomMembership(let target, let targetName, let change, let reason):
      let action: Action
      let phrase: String
      let targeted: Bool
      let important: Bool
      switch change {
      case .joined: (action, phrase, targeted, important) = (.joined, "joined", false, false)
      case .left: (action, phrase, targeted, important) = (.left, "left the room", false, false)
      case .invitationAccepted:
        (action, phrase, targeted, important) = (
          .invitationAccepted, "accepted an invitation", false, false
        )
      case .invitationRejected:
        (action, phrase, targeted, important) = (
          .invitationRejected, "rejected an invitation", false, false
        )
      case .knocked:
        (action, phrase, targeted, important) = (.knocked, "requested to join", false, false)
      case .knockRetracted:
        (action, phrase, targeted, important) = (
          .knockRetracted, "retracted their join request", false, false
        )
      case .invited: (action, phrase, targeted, important) = (.invited, "invited", true, false)
      case .banned: (action, phrase, targeted, important) = (.banned, "banned", true, true)
      case .unbanned: (action, phrase, targeted, important) = (.unbanned, "unbanned", true, true)
      case .kicked: (action, phrase, targeted, important) = (.kicked, "kicked", true, true)
      case .kickedAndBanned:
        (action, phrase, targeted, important) = (.kickedAndBanned, "kicked and banned", true, true)
      case .invitationRevoked:
        (action, phrase, targeted, important) = (
          .invitationRevoked, "revoked the invitation for", true, true
        )
      case .knockAccepted:
        (action, phrase, targeted, important) = (
          .knockAccepted, "accepted the join request from", true, false
        )
      case .knockDenied:
        (action, phrase, targeted, important) = (
          .knockDenied, "denied the join request from", true, true
        )
      default: return nil
      }
      // Self-service transitions with a different sender are ambiguous. Preserve both identities.
      if !targeted && target != event.sender {
        return Descriptor(
          key: Key(action: action, actor: event.sender, target: target, reason: reason),
          phrase: "recorded that",
          targetName: targetName.flatMap { $0.isEmpty ? nil : $0 } ?? target,
          targetSuffix: " " + phrase,
          isImportant: important)
      }
      return Descriptor(
        key: Key(
          action: action, actor: targeted ? event.sender : nil, reason: reason),
        phrase: phrase,
        targetID: targeted ? target : nil,
        targetName: targeted ? (targetName.flatMap { $0.isEmpty ? nil : $0 } ?? target) : nil,
        actorName: targeted ? senderName(event) : nil,
        isImportant: important)
    case .state(let stateKey, let content):
      let setting: Setting
      switch content {
      case .roomAvatar: setting = .avatar
      case .roomCanonicalAlias: setting = .canonicalAlias
      case .roomCreate: setting = .create
      case .roomEncryption: setting = .encryption
      case .roomGuestAccess: setting = .guestAccess
      case .roomHistoryVisibility: setting = .historyVisibility
      case .roomJoinRules: setting = .joinRules
      case .roomName: setting = .name
      case .roomPinnedEvents: setting = .pinnedEvents
      case .roomPowerLevels: setting = .powerLevels
      case .roomServerAcl: setting = .serverAcl
      case .roomThirdPartyInvite: setting = .thirdPartyInvite
      case .roomTombstone: setting = .tombstone
      case .roomTopic: setting = .topic
      case .spaceChild: setting = .spaceChild
      case .spaceParent: setting = .spaceParent
      default: return nil
      }
      // Nonempty keys can identify targets (space children, invitations, etc.). Keep their details.
      guard stateKey.isEmpty else { return nil }
      return Descriptor(
        key: Key(action: .setting(setting), stateKey: stateKey),
        phrase: setting.phrase, isImportant: setting.isImportant)
    default: return nil
    }
  }

  private static func isPolicyRule(_ content: TimelineItemContent) -> Bool {
    guard case .state(_, let state) = content else { return false }
    switch state {
    case .policyRuleRoom, .policyRuleServer, .policyRuleUser: return true
    default: return false
    }
  }
}

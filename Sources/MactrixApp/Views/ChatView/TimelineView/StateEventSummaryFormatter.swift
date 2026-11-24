import MatrixIntegration
import MatrixRustSDK

/// Semantic summaries are independent of row/controller state and of localized SDK descriptions.
enum StateEventSummaryFormatter {
  struct Segment: Equatable {
    let text: String
    var userId: String? = nil
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

    init?(_ change: MembershipChange) {
      switch change {
      case .joined: self = .joined
      case .left: self = .left
      case .invitationAccepted: self = .invitationAccepted
      case .invitationRejected: self = .invitationRejected
      case .knocked: self = .knocked
      case .knockRetracted: self = .knockRetracted
      case .invited: self = .invited
      case .banned: self = .banned
      case .unbanned: self = .unbanned
      case .kicked: self = .kicked
      case .kickedAndBanned: self = .kickedAndBanned
      case .invitationRevoked: self = .invitationRevoked
      case .knockAccepted: self = .knockAccepted
      case .knockDenied: self = .knockDenied
      default: return nil
      }
    }

    var isImportant: Bool {
      switch self {
      case .banned, .unbanned, .kicked, .kickedAndBanned, .invitationRevoked, .knockDenied:
        true
      case .setting(let setting): setting.isImportant
      default: false
      }
    }

    /// The membership sentence. Profile and setting changes have their templates elsewhere.
    var template: Template? {
      switch self {
      case .joined:
        .subjects(
          { String(localized: "stateSummary.joined.one", defaultValue: "\($0) joined") },
          { String(localized: "stateSummary.joined.other", defaultValue: "\($0) joined") })
      case .left:
        .subjects(
          { String(localized: "stateSummary.left.one", defaultValue: "\($0) left the room") },
          { String(localized: "stateSummary.left.other", defaultValue: "\($0) left the room") })
      case .invitationAccepted:
        .subjects(
          {
            String(
              localized: "stateSummary.invitationAccepted.one",
              defaultValue: "\($0) accepted an invitation")
          },
          {
            String(
              localized: "stateSummary.invitationAccepted.other",
              defaultValue: "\($0) accepted an invitation")
          })
      case .invitationRejected:
        .subjects(
          {
            String(
              localized: "stateSummary.invitationRejected.one",
              defaultValue: "\($0) rejected an invitation")
          },
          {
            String(
              localized: "stateSummary.invitationRejected.other",
              defaultValue: "\($0) rejected an invitation")
          })
      case .knocked:
        .subjects(
          {
            String(localized: "stateSummary.knocked.one", defaultValue: "\($0) requested to join")
          },
          {
            String(localized: "stateSummary.knocked.other", defaultValue: "\($0) requested to join")
          })
      case .knockRetracted:
        .subjects(
          {
            String(
              localized: "stateSummary.knockRetracted.one",
              defaultValue: "\($0) retracted their join request")
          },
          {
            String(
              localized: "stateSummary.knockRetracted.other",
              defaultValue: "\($0) retracted their join request")
          })
      case .invited:
        .targeted {
          String(localized: "stateSummary.invited", defaultValue: "\($0) invited \($1)")
        }
      case .banned:
        .targeted {
          String(localized: "stateSummary.banned", defaultValue: "\($0) banned \($1)")
        }
      case .unbanned:
        .targeted {
          String(localized: "stateSummary.unbanned", defaultValue: "\($0) unbanned \($1)")
        }
      case .kicked:
        .targeted {
          String(localized: "stateSummary.kicked", defaultValue: "\($0) kicked \($1)")
        }
      case .kickedAndBanned:
        .targeted {
          String(
            localized: "stateSummary.kickedAndBanned", defaultValue: "\($0) kicked and banned \($1)"
          )
        }
      case .invitationRevoked:
        .targeted {
          String(
            localized: "stateSummary.invitationRevoked",
            defaultValue: "\($0) revoked the invitation for \($1)")
        }
      case .knockAccepted:
        .targeted {
          String(
            localized: "stateSummary.knockAccepted",
            defaultValue: "\($0) accepted the join request from \($1)")
        }
      case .knockDenied:
        .targeted {
          String(
            localized: "stateSummary.knockDenied",
            defaultValue: "\($0) denied the join request from \($1)")
        }
      default: nil
      }
    }

    /// The sentence for a self-service change that someone else sent, or nil for actions that
    /// always have an actor and a target.
    var recordedTemplate: Template? {
      switch self {
      case .joined:
        .recorded {
          String(
            localized: "stateSummary.joined.recorded",
            defaultValue: "\($0) recorded that \($1) joined")
        }
      case .left:
        .recorded {
          String(
            localized: "stateSummary.left.recorded",
            defaultValue: "\($0) recorded that \($1) left the room")
        }
      case .invitationAccepted:
        .recorded {
          String(
            localized: "stateSummary.invitationAccepted.recorded",
            defaultValue: "\($0) recorded that \($1) accepted an invitation")
        }
      case .invitationRejected:
        .recorded {
          String(
            localized: "stateSummary.invitationRejected.recorded",
            defaultValue: "\($0) recorded that \($1) rejected an invitation")
        }
      case .knocked:
        .recorded {
          String(
            localized: "stateSummary.knocked.recorded",
            defaultValue: "\($0) recorded that \($1) requested to join")
        }
      case .knockRetracted:
        .recorded {
          String(
            localized: "stateSummary.knockRetracted.recorded",
            defaultValue: "\($0) recorded that \($1) retracted their join request")
        }
      default: nil
      }
    }
  }

  private enum Setting: String, Hashable {
    case avatar, canonicalAlias, create, encryption, guestAccess, historyVisibility
    case joinRules, name, pinnedEvents, powerLevels, serverAcl, thirdPartyInvite
    case tombstone, topic, spaceChild, spaceParent

    var template: Template {
      switch self {
      case .avatar:
        .subjects(
          {
            String(
              localized: "stateSummary.room.avatar.one", defaultValue: "\($0) changed room avatar")
          },
          {
            String(
              localized: "stateSummary.room.avatar.other", defaultValue: "\($0) changed room avatar"
            )
          })
      case .canonicalAlias:
        .subjects(
          {
            String(
              localized: "stateSummary.room.canonicalAlias.one",
              defaultValue: "\($0) changed room canonical alias")
          },
          {
            String(
              localized: "stateSummary.room.canonicalAlias.other",
              defaultValue: "\($0) changed room canonical alias")
          })
      case .create:
        .subjects(
          { String(localized: "stateSummary.room.create.one", defaultValue: "\($0) created room") },
          {
            String(localized: "stateSummary.room.create.other", defaultValue: "\($0) created room")
          })
      case .encryption:
        .subjects(
          {
            String(
              localized: "stateSummary.room.encryption.one",
              defaultValue: "\($0) changed room encryption")
          },
          {
            String(
              localized: "stateSummary.room.encryption.other",
              defaultValue: "\($0) changed room encryption")
          })
      case .guestAccess:
        .subjects(
          {
            String(
              localized: "stateSummary.room.guestAccess.one",
              defaultValue: "\($0) changed room guest access")
          },
          {
            String(
              localized: "stateSummary.room.guestAccess.other",
              defaultValue: "\($0) changed room guest access")
          })
      case .historyVisibility:
        .subjects(
          {
            String(
              localized: "stateSummary.room.historyVisibility.one",
              defaultValue: "\($0) changed room history visibility")
          },
          {
            String(
              localized: "stateSummary.room.historyVisibility.other",
              defaultValue: "\($0) changed room history visibility")
          })
      case .joinRules:
        .subjects(
          {
            String(
              localized: "stateSummary.room.joinRules.one",
              defaultValue: "\($0) changed room join rules")
          },
          {
            String(
              localized: "stateSummary.room.joinRules.other",
              defaultValue: "\($0) changed room join rules")
          })
      case .name:
        .subjects(
          {
            String(localized: "stateSummary.room.name.one", defaultValue: "\($0) changed room name")
          },
          {
            String(
              localized: "stateSummary.room.name.other", defaultValue: "\($0) changed room name")
          })
      case .pinnedEvents:
        .subjects(
          {
            String(
              localized: "stateSummary.room.pinnedEvents.one",
              defaultValue: "\($0) changed room pinned events")
          },
          {
            String(
              localized: "stateSummary.room.pinnedEvents.other",
              defaultValue: "\($0) changed room pinned events")
          })
      case .powerLevels:
        .subjects(
          {
            String(
              localized: "stateSummary.room.powerLevels.one",
              defaultValue: "\($0) changed room power levels")
          },
          {
            String(
              localized: "stateSummary.room.powerLevels.other",
              defaultValue: "\($0) changed room power levels")
          })
      case .serverAcl:
        .subjects(
          {
            String(
              localized: "stateSummary.room.serverAcl.one",
              defaultValue: "\($0) changed room server ACL")
          },
          {
            String(
              localized: "stateSummary.room.serverAcl.other",
              defaultValue: "\($0) changed room server ACL")
          })
      case .thirdPartyInvite:
        .subjects(
          {
            String(
              localized: "stateSummary.room.thirdPartyInvite.one",
              defaultValue: "\($0) changed room third party invite")
          },
          {
            String(
              localized: "stateSummary.room.thirdPartyInvite.other",
              defaultValue: "\($0) changed room third party invite")
          })
      case .tombstone:
        .subjects(
          {
            String(
              localized: "stateSummary.room.tombstone.one", defaultValue: "\($0) replaced the room")
          },
          {
            String(
              localized: "stateSummary.room.tombstone.other",
              defaultValue: "\($0) replaced the room")
          })
      case .topic:
        .subjects(
          {
            String(
              localized: "stateSummary.room.topic.one", defaultValue: "\($0) changed room topic")
          },
          {
            String(
              localized: "stateSummary.room.topic.other", defaultValue: "\($0) changed room topic")
          })
      case .spaceChild:
        .subjects(
          {
            String(
              localized: "stateSummary.room.spaceChild.one",
              defaultValue: "\($0) changed space child")
          },
          {
            String(
              localized: "stateSummary.room.spaceChild.other",
              defaultValue: "\($0) changed space child")
          })
      case .spaceParent:
        .subjects(
          {
            String(
              localized: "stateSummary.room.spaceParent.one",
              defaultValue: "\($0) changed space parent")
          },
          {
            String(
              localized: "stateSummary.room.spaceParent.other",
              defaultValue: "\($0) changed space parent")
          })
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

  /// A localized sentence. Names are passed in as placeholders and later replaced by segments,
  /// so translations can reorder them and pick the verb form for one or several subjects.
  private enum Template {
    /// The participants did something themselves: "Alice and Bob joined".
    case subjects(_ one: (String) -> String, _ other: (String) -> String)
    /// The actor did something to the participants: "Alice banned Bob and Charlie".
    case targeted((_ actor: String, _ targets: String) -> String)
    /// The participants recorded a self-service change for the target: "Alice recorded that Bob
    /// joined".
    case recorded((_ actors: String, _ target: String) -> String)
  }

  private struct Descriptor {
    let key: Key
    let template: Template
    var targetID: String? = nil
    var targetName: String? = nil
    var actorName: String? = nil
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
              Segment(text: name, userId: event.sender),
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
        members.append([
          Segment(
            text: omitted == 1
              ? String(localized: "1 other event") : String(localized: "\(omitted) other events"))
        ])
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
    let subjects = participantSegments(participants)
    var segments: [Segment]
    switch descriptor.template {
    case .subjects(let one, let other):
      let template = participants.count == 1 ? one : other
      segments = compose(template(placeholder(0)), [subjects])
    case .targeted(let template):
      let actor = Segment(text: descriptor.actorName ?? "", userId: descriptor.key.actor)
      segments = compose(template(placeholder(0), placeholder(1)), [[actor], subjects])
    case .recorded(let template):
      let target = Segment(text: descriptor.targetName ?? "", userId: descriptor.key.target)
      segments = compose(template(placeholder(0), placeholder(1)), [subjects, [target]])
    }
    if let reason = descriptor.key.reason {
      segments = compose(
        String(localized: "\(placeholder(0)) because \(reason)"), [segments])
    }
    let count = participants.reduce(0) { $0 + $1.count }
    if participants.count == 1 && count > 1 {
      segments = compose(String(localized: "\(placeholder(0)) \(count) times"), [segments])
    }
    return Clause(
      segments: segments, eventCount: count, firstIndex: participants[0].firstIndex,
      isImportant: descriptor.isImportant)
  }

  private static func participantSegments(_ participants: [Participant]) -> [Segment] {
    let first = [Segment(text: participants[0].name, userId: participants[0].id)]
    if participants.count == 2 {
      return compose(
        String(localized: "\(placeholder(0)) and \(placeholder(1))"),
        [first, [Segment(text: participants[1].name, userId: participants[1].id)]])
    } else if participants.count > 2 {
      return compose(
        String(localized: "\(placeholder(0)) and \(participants.count - 1) others"), [first])
    }
    return first
  }

  /// Marks where argument `index` goes in a localized template. Private-use characters can't
  /// appear in translations, so they are safe to split on.
  static func placeholder(_ index: Int) -> String {
    String(Character(UnicodeScalar(0xF8F0 + UInt32(index))!))
  }

  /// Replaces the placeholders in a localized template with the argument segments, keeping
  /// their user IDs. Adjacent plain text is merged into a single segment.
  static func compose(_ template: String, _ arguments: [[Segment]]) -> [Segment] {
    var result: [Segment] = []
    func append(_ segment: Segment) {
      if segment.userId == nil, let last = result.last, last.userId == nil {
        result[result.count - 1] = Segment(text: last.text + segment.text)
      } else {
        result.append(segment)
      }
    }
    for character in template {
      if let index = arguments.indices.first(where: { placeholder($0) == String(character) }) {
        arguments[index].forEach(append)
      } else {
        append(Segment(text: String(character)))
      }
    }
    return result
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
          key: Key(action: .displayNameAndAvatar),
          template:
            .subjects(
              {
                String(
                  localized: "stateSummary.displayNameAndAvatar.one",
                  defaultValue: "\($0) changed their display name and avatar")
              },
              {
                String(
                  localized: "stateSummary.displayNameAndAvatar.other",
                  defaultValue: "\($0) changed their display name and avatar")
              }))
      case (true, false):
        return Descriptor(
          key: Key(action: .displayName),
          template:
            .subjects(
              {
                String(
                  localized: "stateSummary.displayName.one",
                  defaultValue: "\($0) changed their display name")
              },
              {
                String(
                  localized: "stateSummary.displayName.other",
                  defaultValue: "\($0) changed their display name")
              }))
      case (false, true):
        return Descriptor(
          key: Key(action: .avatar),
          template:
            .subjects(
              {
                String(
                  localized: "stateSummary.avatar.one", defaultValue: "\($0) changed their avatar")
              },
              {
                String(
                  localized: "stateSummary.avatar.other", defaultValue: "\($0) changed their avatar"
                )
              }))
      case (false, false): return nil
      }
    case .roomMembership(let target, let targetName, let change, let reason):
      guard let change, let action = Action(change) else { return nil }
      let targetName = targetName.flatMap { $0.isEmpty ? nil : $0 } ?? target
      // Self-service transitions with a different sender are ambiguous. Preserve both identities.
      if let recorded = action.recordedTemplate, target != event.sender {
        return Descriptor(
          key: Key(action: action, actor: event.sender, target: target, reason: reason),
          template: recorded, targetName: targetName, isImportant: action.isImportant)
      }
      guard let template = action.template else { return nil }
      let targeted = action.recordedTemplate == nil
      return Descriptor(
        key: Key(action: action, actor: targeted ? event.sender : nil, reason: reason),
        template: template,
        targetID: targeted ? target : nil,
        targetName: targeted ? targetName : nil,
        actorName: targeted ? senderName(event) : nil,
        isImportant: action.isImportant)
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
        template: setting.template, isImportant: setting.isImportant)
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

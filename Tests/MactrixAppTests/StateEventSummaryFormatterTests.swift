import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

struct StateEventSummaryFormatterTests {
  @Test func nonconsecutiveActionsGroupInFirstOccurrenceOrder() {
    let result = summary([
      joined("alice", "Alice"), profile("bob", "Bob"), joined("charlie", "Charlie"),
    ])
    #expect(result.text == "Alice and Charlie joined, Bob changed their display name")
    #expect(result.omittedEventCount == 0)
  }

  @Test func threeGroupsUseOnlyCommasWithoutChangingParticipantAnd() {
    let result = summary([
      joined("a", "Alice"), profile("b", "Bob"),
      joined("c", "Charlie"),
      event("d", "Dave", .state(stateKey: "", content: .roomTopic(topic: "Topic"))),
    ])
    #expect(
      result.text
        == "Alice and Charlie joined, Bob changed their display name, Dave changed room topic")
    #expect(result.omittedEventCount == 0)
  }

  @Test func omissionIsFinalListMemberWithMultipleVisibleGroups() {
    let visible = [
      joined("a", "Alice"), joined("c", "Charlie"), profile("b", "Bob"),
    ]
    let extra = event("d", "Dave", .state(stateKey: "", content: .roomName(name: "Room")))
    let omitted = Array(repeating: profile("long", String(repeating: "X", count: 250)), count: 3)
    let cases: [([EventTimelineItem], String)] = [
      (visible, "Alice and Charlie joined, Bob changed their display name, 3 other events"),
      (
        visible + [extra],
        "Alice and Charlie joined, Bob changed their display name, Dave changed room name, 3 other events"
      ),
    ]
    for (events, expected) in cases {
      let result = summary(events + omitted, budget: expected.count)
      #expect(result.text == expected)
      #expect(result.omittedEventCount == 3)
      #expect(result.text.count == expected.count)
    }
  }

  @Test func manyUsersUseDistinctIdentityCount() {
    let result = summary([
      joined("alice", "Alice"), joined("bob", "Bob"), joined("charlie", "Charlie"),
      joined("dave", "Dave"),
    ])
    #expect(result.text == "Alice and 3 others joined")
  }

  @Test func repeatedActionsNeverPoolCountsAcrossUsers() {
    let result = summary([
      profile("alice", "Alice"), profile("bob", "Bob"), profile("alice", "Alice"),
      profile("bob", "Bob"), profile("alice", "Alice"),
    ])
    #expect(
      result.text
        == "Alice changed their display name 3 times, Bob changed their display name 2 times")
    #expect(!result.text.contains("in total"))
  }

  @Test func repeatedAndSingleUsersRemainSeparateClauses() {
    let result = summary([
      profile("alice", "Alice"), profile("bob", "Bob"), profile("alice", "New Alice"),
      profile("charlie", "Charlie"),
    ])
    #expect(
      result.text
        == "Alice changed their display name 2 times, Bob and Charlie changed their display name"
    )
  }

  @Test func idsNotDisplayNamesDefineIdentity() {
    #expect(summary([joined("a", "Same"), joined("b", "Same")]).text == "Same and Same joined")
    #expect(
      summary([profile("a", "Old"), profile("a", "New")]).text
        == "Old changed their display name 2 times")
    #expect(summary([joined("a", nil)]).text == "@a:example.org joined")
    #expect(summary([joined("a", "")]).text == "@a:example.org joined")
  }

  @Test func profileKindsIncludeAdditionsRemovalsAndCombinedChanges() {
    let events = [
      profile("a", "Alice"),
      event(
        "a", "Alice",
        .profileChange(
          displayName: nil, prevDisplayName: nil,
          avatarUrl: "avatar", prevAvatarUrl: nil)),
      event(
        "a", "Alice",
        .profileChange(
          displayName: "New", prevDisplayName: "Old",
          avatarUrl: "new", prevAvatarUrl: "old")),
      event(
        "a", "Alice",
        .profileChange(
          displayName: nil, prevDisplayName: "Old",
          avatarUrl: nil, prevAvatarUrl: nil)),
    ]
    #expect(
      summary(events, budget: 1000).text
        == "Alice changed their display name 2 times, Alice changed their avatar, Alice changed their display name and avatar"
    )
  }

  @Test func roomSettingsHaveDistinctSemanticKinds() {
    let events = [
      event("a", "Alice", .state(stateKey: "", content: .roomName(name: "One"))),
      event("a", "Alice", .state(stateKey: "", content: .roomTopic(topic: "Topic"))),
      event("a", "Alice", .state(stateKey: "", content: .roomName(name: "Two"))),
      event("a", "Alice", .state(stateKey: "", content: .roomEncryption)),
    ]
    #expect(
      summary(events, budget: 1000).text
        == "Alice changed room name 2 times, Alice changed room topic, Alice changed room encryption"
    )
  }

  @Test func moderationPreservesActorsTargetsActionsAndReasons() {
    let events = [
      membership("a", "Alice", target: "b", name: "Bob", change: .banned),
      membership("c", "Charlie", target: "b", name: "Bob", change: .banned),
      membership("a", "Alice", target: "d", name: "Dave", change: .banned),
      membership("a", "Alice", target: "b", name: "Bob", change: .kicked),
      membership("a", "Alice", target: "b", name: "Bob", change: .banned, reason: "spam"),
      membership("a", "Alice", target: "b", name: "Bob", change: .banned),
    ]
    #expect(
      summary(events, budget: 1000).text
        == "Alice banned Bob 2 times, Charlie banned Bob, Alice banned Dave, Alice kicked Bob, Alice banned Bob because spam"
    )
  }

  @Test func membershipKindsRemainDistinct() {
    let selfChanges: [(MembershipChange, String)] = [
      (.joined, "joined"), (.left, "left the room"),
      (.invitationAccepted, "accepted an invitation"),
      (.invitationRejected, "rejected an invitation"),
      (.knocked, "requested to join"), (.knockRetracted, "retracted their join request"),
    ]
    #expect(
      summary(
        selfChanges.map {
          membership("a", "Alice", target: "a", name: "Alice", change: $0.0)
        }, budget: 1000
      ).text == selfChanges.map { "Alice " + $0.1 }.joined(separator: ", "))
    let targetedChanges: [(MembershipChange, String)] = [
      (.invited, "invited"), (.banned, "banned"), (.unbanned, "unbanned"),
      (.kicked, "kicked"), (.kickedAndBanned, "kicked and banned"),
      (.invitationRevoked, "revoked the invitation for"),
      (.knockAccepted, "accepted the join request from"),
      (.knockDenied, "denied the join request from"),
    ]
    #expect(
      summary(
        targetedChanges.flatMap { change, _ in
          [
            membership("a", "Alice", target: "b", name: "Bob", change: change),
            membership("a", "Alice", target: "c", name: "Charlie", change: change),
          ]
        }, budget: 1000
      ).text == targetedChanges.map { "Alice " + $0.1 + " Bob and Charlie" }
        .joined(separator: ", "))
  }

  @Test func unavailableProfilesUseIDs() {
    var value = joined("a", "Alice")
    value.senderProfile = .unavailable
    #expect(summary([value]).text == "@a:example.org joined")
  }

  @Test func targetIDsAndFallbacksAreNotDisplayNameKeys() {
    let events = [
      membership("a", "Alice", target: "b", name: "Same", change: .invited),
      membership("a", "Alice", target: "c", name: "Same", change: .invited),
      membership("a", "Alice", target: "d", name: nil, change: .kicked),
    ]
    #expect(
      summary(events).text
        == "Alice invited Same and Same, Alice kicked @d:example.org")
  }

  @Test func targetedActionsGroupNonconsecutiveTargetsAndPreserveNameEmphasis() {
    let result = summary([
      membership("a", "Alice", target: "b", name: "Bob", change: .invited),
      profile("d", "Dave"),
      membership("a", "New Alice", target: "c", name: "Charlie", change: .invited),
    ])
    #expect(result.text == "Alice invited Bob and Charlie, Dave changed their display name")
    #expect(result.omittedEventCount == 0)
    #expect(result.segments.filter(\.isName).map(\.text) == ["Alice", "Bob", "Charlie", "Dave"])
    #expect(
      result.segments.filter { !$0.isName }.allSatisfy {
        !["Alice", "Bob", "Charlie", "Dave"].contains($0.text)
      })
  }

  @Test func manyTargetsUseFirstTargetAndDistinctIdentityCount() {
    let events = ["b", "c", "d", "e"].map {
      membership("a", "Alice", target: $0, name: "Same", change: .invited)
    }
    for count in [3, 4] {
      let result = summary(Array(events.prefix(count)))
      #expect(result.text == "Alice invited Same and \(count - 1) others")
      #expect(result.omittedEventCount == 0)
      #expect(result.segments.filter(\.isName).map(\.text) == ["Alice", "Same"])
    }
  }

  @Test func repeatedTargetsNeverPoolCountsAndUseFirstNames() {
    let result = summary([
      membership("a", "Alice", target: "b", name: "Bob", change: .invited),
      membership("a", "Alice", target: "c", name: "Charlie", change: .invited),
      membership("a", "New Alice", target: "b", name: "New Bob", change: .invited),
      membership("a", "Alice", target: "c", name: "Charlie", change: .invited),
      membership("a", "Alice", target: "b", name: "Bob", change: .invited),
    ])
    #expect(result.text == "Alice invited Bob 3 times, Alice invited Charlie 2 times")
    #expect(result.omittedEventCount == 0)
  }

  @Test func repeatedTargetsAndSinglesRemainSeparateInSourceOrder() {
    let result = summary([
      membership("a", "Alice", target: "b", name: "Bob", change: .invited),
      profile("e", "Eve"),
      membership("a", "Alice", target: "c", name: "Charlie", change: .invited),
      membership("a", "Alice", target: "b", name: "Bob", change: .invited),
      membership("a", "Alice", target: "d", name: "Dave", change: .invited),
    ])
    #expect(
      result.text
        == "Alice invited Bob 2 times, Eve changed their display name, Alice invited Charlie and Dave"
    )
    #expect(result.omittedEventCount == 0)
  }

  @Test func targetedGroupsKeepActorIDsActionsAndReasonsDistinct() {
    let result = summary(
      [
        membership("a", "Same", target: "b", name: "Bob", change: .banned, reason: "spam"),
        membership("other", "Same", target: "c", name: "Charlie", change: .banned, reason: "spam"),
        membership("a", "Same", target: "d", name: "Dave", change: .banned, reason: "spam"),
        membership("a", "Same", target: "c", name: "Charlie", change: .banned, reason: "abuse"),
        membership("a", "Same", target: "c", name: "Charlie", change: .banned),
        membership("a", "Same", target: "c", name: "Charlie", change: .kicked, reason: "spam"),
      ], budget: 1000)
    #expect(
      result.text
        == "Same banned Bob and Dave because spam, Same banned Charlie because spam, Same banned Charlie because abuse, Same banned Charlie, Same kicked Charlie because spam"
    )
  }

  @Test func identicalTargetNamesKeepSeparateRepeatCountsAndFirstOccurrences() {
    let result = summary([
      membership("a", "Alice", target: "b", name: "Same", change: .invited),
      membership("a", "Alice", target: "c", name: "Same", change: .invited),
      membership("a", "Alice", target: "b", name: "Renamed", change: .invited),
      membership("a", "Alice", target: "d", name: "", change: .invited),
    ])
    #expect(result.text == "Alice invited Same 2 times, Alice invited Same and @d:example.org")
  }

  @Test func targetedOmissionCountsUnderlyingEventsNotVisibleNamesOrClauses() {
    let invitations = ["b", "c", "d"].map {
      membership("a", "Alice", target: $0, name: "Target", change: .invited)
    }
    let repeats = Array(
      repeating: membership("a", "Alice", target: "e", name: "Eve", change: .invited), count: 3)
    let events = [joined("f", "Frank")] + invitations + repeats
    let omitted = summary(events, budget: "Frank joined, 6 other events".count)
    #expect(omitted.text == "Frank joined, 6 other events")
    #expect(omitted.omittedEventCount == 6)
    let visibleText = "Frank joined, Alice invited Target and 2 others, 3 other events"
    let visible = summary(events, budget: visibleText.count)
    #expect(visible.text == visibleText)
    #expect(visible.omittedEventCount == 3)
    let repeatedText = "Alice invited Eve 3 times, 4 other events"
    let repeated = summary(
      repeats + [joined("f", "Frank")] + invitations, budget: repeatedText.count)
    #expect(repeated.text == repeatedText)
    #expect(repeated.omittedEventCount == 4)
  }

  @Test func ambiguousSelfTransitionsDoNotMergeTargetsOrSelfServiceEvents() {
    let result = summary(
      [
        membership("a", "Alice", target: "b", name: "Bob", change: .joined),
        joined("a", "Alice"),
        membership("a", "Alice", target: "c", name: "Charlie", change: .joined),
        membership("a", "Alice", target: "b", name: "New Bob", change: .joined),
        joined("b", "Bob"),
      ], budget: 1000)
    #expect(
      result.text
        == "Alice recorded that Bob joined 2 times, Alice and Bob joined, Alice recorded that Charlie joined"
    )
    #expect(result.omittedEventCount == 0)
  }

  @Test func differentActorOnSelfTransitionDoesNotBecomeActorJoined() {
    let result = summary([
      membership("a", "Alice", target: "b", name: "Bob", change: .joined)
    ])
    #expect(result.text == "Alice recorded that Bob joined")
  }

  @Test func unknownAndFailedContentNeverAggregate() {
    let contents: [TimelineItemContent] = [
      .roomMembership(userId: "@a:example.org", userDisplayName: nil, change: nil, reason: nil),
      .roomMembership(
        userId: "@a:example.org", userDisplayName: nil, change: .notImplemented, reason: nil),
      .profileChange(displayName: nil, prevDisplayName: nil, avatarUrl: nil, prevAvatarUrl: nil),
      .state(stateKey: "", content: .custom(eventType: "custom.type")),
      .failedToParseState(eventType: "custom", stateKey: "target", error: "invalid"),
      .failedToParseMessageLike(eventType: "custom", error: "invalid"),
      .callInvite,
    ]
    for content in contents {
      let value = event("a", "Alice", content)
      #expect(
        summary([value, value], budget: 10000).text
          == "Alice \(content.userInterfaceText), Alice \(content.userInterfaceText)")
    }
  }

  @Test func nonemptyStateKeysDoNotMerge() {
    let a = event("a", "Alice", .state(stateKey: "child-one", content: .spaceChild))
    let b = event("a", "Alice", .state(stateKey: "child-two", content: .spaceChild))
    #expect(summary([a, b]).text == "Alice changed space child, Alice changed space child")
  }

  @Test func budgetCountsOmittedUnderlyingEventsAndRetainsCompleteClauses() {
    let events =
      [joined("a", "Alice")] + Array(repeating: profile("b", "Bob"), count: 3)
      + [event("c", "Charlie", .state(stateKey: "", content: .roomTopic(topic: "Topic")))]
    let result = summary(events, budget: 45)
    #expect(result.text == "Alice joined, 4 other events")
    #expect(result.omittedEventCount == 4)
    #expect(result.text.count <= 45)
    let tiny = summary(events, budget: 1)
    #expect(tiny.text == "Alice joined, 4 other events")
    #expect(summary([]).text.isEmpty)
  }

  @Test func budgetIncludesSuffixAndHasExactBoundary() {
    let events = [joined("a", "Alice"), profile("b", "Bob")]
    let full = summary(events)
    #expect(summary(events, budget: full.text.count).text == full.text)
    let shortened = summary(events, budget: full.text.count - 1)
    #expect(shortened.text == "Alice joined, 1 other event")
    let longName = String(repeating: "A", count: 200)
    #expect(summary([joined("a", longName)], budget: 180).text == longName + " joined")
  }

  @Test func moderationAndSecurityWinBudgetButRenderInSourceOrder() {
    let events = [
      profile("a", "Alice"),
      membership("b", "Bob", target: "d", name: "Dave", change: .banned),
      joined("c", "Charlie"),
      event("e", "Eve", .state(stateKey: "", content: .roomEncryption)),
    ]
    let result = summary(events, budget: 70)
    #expect(result.text == "Bob banned Dave, Eve changed room encryption, 2 other events")
    #expect(result.omittedEventCount == 2)
    #expect(result.text.count <= 70)
    #expect(
      summary(events, budget: 1000).text.hasPrefix(
        "Alice changed their display name, Bob banned Dave"))
  }

  @Test @MainActor func rowUsesSummaryForAttributedTextAndMeasurement() throws {
    let events = [joined("a", "Alice"), joined("c", "Charlie")]
    let entries = events.map {
      TimelineItemRowInfo.StateEntry(item: TimelineItem(noHandle: .init()), event: $0)
    }
    let row = StateEventRowView()
    row.configure(items: entries)
    let field = try #require(
      row.subviews.compactMap { $0 as? NSTextField }.first {
        $0.attributedStringValue.string == "Alice and Charlie joined"
      })
    let attributed = field.attributedStringValue
    let nameFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: nameFont).contains(.boldFontMask))
    let bodyFont = try #require(attributed.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: bodyFont).contains(.italicFontMask))
    let width: CGFloat = 200
    let measured = attributed.boundingRect(
      with: NSSize(width: width - 74, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height
    #expect(StateEventRowView.height(for: entries, width: width) == max(ceil(measured), 28))
  }
}

private func summary(_ events: [EventTimelineItem], budget: Int = 180)
  -> StateEventSummaryFormatter.Summary
{
  StateEventSummaryFormatter.summary(for: events, characterBudget: budget)
}

private func joined(_ id: String, _ name: String?) -> EventTimelineItem {
  membership(id, name, target: id, name: name, change: .joined)
}

private func profile(_ id: String, _ name: String) -> EventTimelineItem {
  event(
    id, name,
    .profileChange(displayName: "New", prevDisplayName: "Old", avatarUrl: nil, prevAvatarUrl: nil))
}

private func membership(
  _ actor: String, _ actorName: String?, target: String, name: String?,
  change: MembershipChange, reason: String? = nil
) -> EventTimelineItem {
  event(
    actor, actorName,
    .roomMembership(
      userId: "@\(target):example.org",
      userDisplayName: name, change: change, reason: reason))
}

private func event(_ id: String, _ name: String?, _ content: TimelineItemContent)
  -> EventTimelineItem
{
  EventTimelineItem(
    isRemote: true, eventOrTransactionId: .eventId(eventId: "event"), sender: "@\(id):example.org",
    senderProfile: .ready(
      displayName: name, displayNameAmbiguous: false, avatarUrl: nil,
      status: nil, call: nil),
    forwarder: nil, forwarderProfile: nil, isOwn: false, isEditable: false,
    content: content, reactions: [], eventTypeRaw: nil, timestamp: 1,
    localSendState: nil, editSendState: nil, redactionSendState: nil, localCreatedAt: nil,
    readReceipts: [:], origin: nil, canBeRepliedTo: false,
    lazyProvider: LazyTimelineItemProvider(noHandle: .init()))
}

import AppKit
import MatrixRustSDK
import Testing

@testable import MactrixApp

struct TimelineRowProjectionTests {
  @Test func emptyTimelineHasOnlyTypingIndicator() {
    var projection = TimelineRowProjection(items: [])
    #expect(projection.rows.map(\.id) == ["typing-indicator"])
    let change = projection.apply([])
    #expect(change.oldIDs == ["typing-indicator"])
    #expect(change.changedIDs.isEmpty)
    expectEquivalent(projection, to: [])
  }

  @Test func allNonMessageEventsFormOneOrderedNonemptyGroup() throws {
    let contents: [TimelineItemContent] = [
      .callInvite,
      .rtcNotification(
        callIntent: nil, declinedBy: [], activeMembers: [], callStartTsMillis: nil, isJoined: false),
      .roomMembership(userId: "@bob:example.org", userDisplayName: nil, change: nil, reason: nil),
      .profileChange(displayName: "Bob", prevDisplayName: nil, avatarUrl: nil, prevAvatarUrl: nil),
      .state(stateKey: "", content: .roomName(name: "Room")),
      .failedToParseMessageLike(eventType: "custom.message", error: "invalid"),
      .failedToParseState(eventType: "custom.state", stateKey: "", error: "invalid"),
    ]
    let items = contents.enumerated().map { index, content in
      event("s\(index)", sender: "@user\(index):example.org", content: content)
    }
    let projection = TimelineRowProjection(items: items)
    #expect(projection.rows.map(\.id) == ["typing-indicator", "state:s0"])
    let row = try #require(projection.rows.last)
    guard case .state(let entries) = row else {
      Issue.record("Expected a grouped state row")
      return
    }
    #expect(!entries.isEmpty)
    #expect(
      entries.map { $0.event.eventOrTransactionId.id }
        == items.map { $0.asEvent()!.eventOrTransactionId.id })
    #expect(entries.map { ObjectIdentifier($0.item) } == items.map(ObjectIdentifier.init))
    #expect(row.timelineItem === items.first)
    expectEquivalent(projection, to: items)
  }

  @Test func messagesAndVirtualItemsBreakRunsWithoutReversingGroupContents() {
    let items = [
      state("a"), state("b"), message("m"), state("c"), marker("v"), state("d"), state("e"),
    ]
    let projection = TimelineRowProjection(items: items)
    #expect(
      projection.rows.map(\.id) == [
        "typing-indicator", "state:d", "virtual:v", "state:c", "message:m", "profile:m", "state:a",
      ])
    #expect(stateGroups(projection) == [["d", "e"], ["c"], ["a", "b"]])
    expectEquivalent(projection, to: items)
  }

  @Test func rowIdentitiesUseFirstEventIDNotSDKItemID() {
    let first = state("a")
    var projection = TimelineRowProjection(items: [first, state("b")])
    #expect(first.uniqueId().id == "sdk:a")
    #expect(projection.rows.map(\.id) == ["typing-indicator", "state:a"])

    let append = projection.apply([.pushBack(value: state("c"))])
    #expect(append.oldIDs == ["typing-indicator", "state:a"])
    #expect(append.changedIDs == ["state:a"])
    #expect(stateGroups(projection) == [["a", "b", "c"]])

    let prepend = projection.apply([.pushFront(value: state("z"))])
    #expect(prepend.changedIDs == ["state:a", "state:z"])
    #expect(projection.rows.map(\.id) == ["typing-indicator", "state:z"])
    let remove = projection.apply([.popFront])
    #expect(remove.changedIDs == ["state:z", "state:a"])
    #expect(projection.rows.map(\.id) == ["typing-indicator", "state:a"])
  }

  @Test func profilesFollowSenderAndResetAfterStateOrVirtualRows() {
    let items = [
      message("a"), message("b"), message("c", sender: "@bob:example.org"),
      state("s1"), state("s2"), message("d", sender: "@bob:example.org"),
      marker("v"), message("e", sender: "@bob:example.org"),
      message("f", sender: "@bob:example.org"),
    ]
    let projection = TimelineRowProjection(items: items)
    #expect(
      projection.rows.map(\.id) == [
        "typing-indicator", "message:f", "message:e", "profile:e", "virtual:v",
        "message:d", "profile:d", "state:s1", "message:c", "profile:c",
        "message:b", "message:a", "profile:a",
      ])
    expectEquivalent(projection, to: items)
  }

  @Test func insertingAndRemovingBreaksUpdatesSuccessorProfile() {
    let a = message("a")
    let b = message("b")
    for separator in [state("s"), marker("v")] {
      var projection = TimelineRowProjection(items: [a, b])
      let inserted = projection.apply([.insert(index: 1, value: separator)])
      #expect(projection.rows.map(\.id).contains("profile:b"))
      #expect(inserted.changedIDs.contains("profile:b"))
      expectEquivalent(projection, to: [a, separator, b])
      let removed = projection.apply([.remove(index: 1)])
      #expect(!projection.rows.map(\.id).contains("profile:b"))
      #expect(removed.changedIDs.contains("profile:b"))
      expectEquivalent(projection, to: [a, b])
    }
  }

  @Test func changingSenderUpdatesProfilesOnBothSides() {
    let a = message("a")
    let b = message("b")
    let c = message("c")
    var projection = TimelineRowProjection(items: [a, b, c])
    let replacement = message("b", sender: "@bob:example.org")
    let change = projection.apply([.set(index: 1, value: replacement)])
    #expect(
      projection.rows.map(\.id) == [
        "typing-indicator", "message:c", "profile:c", "message:b", "profile:b", "message:a",
        "profile:a",
      ])
    #expect(change.changedIDs.isSuperset(of: ["message:b", "profile:b", "profile:c"]))
    expectEquivalent(projection, to: [a, replacement, c])
  }

  @Test func everyDiffMatchesFreshProjection() {
    let a = state("a")
    let b = state("b")
    let m = message("m")
    let c = state("c")
    let d = state("d")
    let original = [a, b, m, c, d]
    let x = state("x")
    let cases: [(String, TimelineDiff, [TimelineItem])] = [
      ("append", .append(values: [x]), original + [x]),
      ("clear", .clear, []),
      ("pushFront", .pushFront(value: x), [x] + original),
      ("pushBack", .pushBack(value: x), original + [x]),
      ("popFront", .popFront, [b, m, c, d]),
      ("popBack", .popBack, [a, b, m, c]),
      ("insert state", .insert(index: 1, value: x), [a, x, b, m, c, d]),
      (
        "insert message splits", .insert(index: 1, value: message("x")),
        [a, message("x"), b, m, c, d]
      ),
      ("set merges", .set(index: 2, value: x), [a, b, x, c, d]),
      ("set splits", .set(index: 1, value: marker("x")), [a, marker("x"), m, c, d]),
      ("remove merges", .remove(index: 2), [a, b, c, d]),
      ("truncate inside group", .truncate(length: 4), [a, b, m, c]),
      ("truncate to zero", .truncate(length: 0), []),
      ("reset", .reset(values: [x, a, marker("v"), m]), [x, a, marker("v"), m]),
    ]
    for (name, diff, expected) in cases {
      var projection = TimelineRowProjection(items: original)
      let oldIDs = projection.rows.map(\.id)
      let change = projection.apply([diff])
      #expect(change.oldIDs == oldIDs, "\(name)")
      expectEquivalent(projection, to: expected)
      let oldSnapshots = snapshots(TimelineRowProjection(items: original))
      let newSnapshots = snapshots(projection)
      for row in oldSnapshots where !newSnapshots.contains(row) {
        #expect(
          change.changedIDs.contains(row.id), "Missing old changed row for \(name): \(row.id)")
      }
      for row in newSnapshots where !oldSnapshots.contains(row) {
        #expect(
          change.changedIDs.contains(row.id), "Missing new changed row for \(name): \(row.id)")
      }
      #expect(!change.changedIDs.contains("typing-indicator"))
    }
  }

  @Test func batchedMergesAndSplitsRetainOriginalOldIDsAndAccumulateChanges() {
    let a = state("a")
    let b = state("b")
    let c = state("c")
    let d = state("d")
    let m = message("m")
    let v = marker("v")
    let x = message("x")
    let original = [a, b, m, c, d]
    let diffs: [TimelineDiff] = [
      .remove(index: 2), .insert(index: 1, value: v), .set(index: 3, value: x),
      .remove(index: 1), .set(index: 2, value: c),
    ]
    var batched = TimelineRowProjection(items: original)
    var sequential = TimelineRowProjection(items: original)
    let oldIDs = batched.rows.map(\.id)
    let change = batched.apply(diffs)
    var union = Set<String>()
    let intermediate: [[TimelineItem]] = [
      [a, b, c, d], [a, v, b, c, d], [a, v, b, x, d], [a, b, x, d], [a, b, c, d],
    ]
    for (diff, expected) in zip(diffs, intermediate) {
      union.formUnion(sequential.apply([diff]).changedIDs)
      expectEquivalent(sequential, to: expected)
    }
    #expect(change.oldIDs == oldIDs)
    #expect(change.changedIDs == union)
    #expect(
      change.changedIDs.isSuperset(of: [
        "state:a", "state:b", "state:c", "state:d", "virtual:v", "message:x", "profile:x",
      ]))
    #expect(snapshots(batched) == snapshots(sequential))
    expectEquivalent(batched, to: [a, b, c, d])
  }

  @Test func editsInvalidateWholeRunButNotDistantRows() {
    let items = [
      message("left"), marker("left-boundary"), state("a"), state("b"), state("c"),
      marker("right-boundary"), message("right"),
    ]
    var projection = TimelineRowProjection(items: items)
    let updated = event("b", content: .callInvite, timestamp: 99)
    let change = projection.apply([.set(index: 3, value: updated)])
    #expect(change.changedIDs == ["state:a"])
    #expect(stateGroups(projection) == [["a", "b", "c"]])
    var expected = items
    expected[3] = updated
    expectEquivalent(projection, to: expected)
  }

  @Test func resetAndClearInvalidateAllOldAndNewRows() {
    var projection = TimelineRowProjection(items: [state("a"), state("b"), message("m")])
    let oldIDs = projection.rows.map(\.id)
    let replacement = [marker("v"), state("c"), state("d")]
    let reset = projection.apply([.reset(values: replacement)])
    #expect(reset.oldIDs == oldIDs)
    #expect(reset.changedIDs == ["state:a", "message:m", "profile:m", "virtual:v", "state:c"])
    expectEquivalent(projection, to: replacement)
    let clear = projection.apply([.clear])
    #expect(clear.changedIDs == ["virtual:v", "state:c"])
    expectEquivalent(projection, to: [])
    #expect(projection.apply([.clear]).changedIDs.isEmpty)
  }

  @Test func emptyAndBoundaryEditsMatchFreshProjection() {
    let a = state("a")
    let b = state("b")
    let v = marker("v")
    let cases: [([TimelineItem], [TimelineDiff], [TimelineItem])] = [
      ([], [.append(values: [a, b])], [a, b]),
      ([], [.pushFront(value: a)], [a]),
      ([], [.pushBack(value: a)], [a]),
      ([], [.insert(index: 0, value: a)], [a]),
      ([a], [.popFront], []),
      ([a], [.popBack], []),
      ([a], [.remove(index: 0)], []),
      ([a, b], [.insert(index: 2, value: v)], [a, b, v]),
      ([a, b], [.append(values: []), .truncate(length: 2)], [a, b]),
      ([a], [.clear, .pushBack(value: b), .reset(values: []), .pushFront(value: a)], [a]),
    ]
    for (original, diffs, expected) in cases {
      var projection = TimelineRowProjection(items: original)
      let change = projection.apply(diffs)
      #expect(change.oldIDs == TimelineRowProjection(items: original).rows.map(\.id))
      expectEquivalent(projection, to: expected)
    }
    var unchanged = TimelineRowProjection(items: [a, b])
    #expect(unchanged.apply([.append(values: []), .truncate(length: 2)]).changedIDs.isEmpty)
  }
}

// These fakes never cross the FFI boundary; all methods used by the projection are overridden.
private final class ProjectionTimelineItem: TimelineItem, @unchecked Sendable {
  private let eventValue: EventTimelineItem?
  private let virtualValue: VirtualTimelineItem?
  private let identifier: String

  init(id: String, event: EventTimelineItem? = nil, virtual: VirtualTimelineItem? = nil) {
    identifier = id
    eventValue = event
    virtualValue = virtual
    super.init(noHandle: .init())
  }

  required init(unsafeFromHandle handle: UInt64) {
    fatalError("Projection fixtures must not use Rust handles")
  }

  override func asEvent() -> EventTimelineItem? { eventValue }
  override func asVirtual() -> VirtualTimelineItem? { virtualValue }
  override func uniqueId() -> TimelineUniqueId { .init(id: identifier) }
  override func fmtDebug() -> String { identifier }
}

private func event(
  _ id: String, sender: String = "@alice:example.org", content: TimelineItemContent,
  timestamp: UInt64 = 1
) -> TimelineItem {
  let value = EventTimelineItem(
    isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: sender,
    senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
    isOwn: false, isEditable: false, content: content, reactions: [], eventTypeRaw: nil,
    timestamp: timestamp, localSendState: nil, editSendState: nil, redactionSendState: nil,
    localCreatedAt: nil, readReceipts: [:], origin: nil, canBeRepliedTo: false,
    lazyProvider: LazyTimelineItemProvider(noHandle: .init()))
  return ProjectionTimelineItem(id: "sdk:\(id)", event: value)
}

private func state(_ id: String) -> TimelineItem {
  event(id, content: .state(stateKey: "", content: .roomName(name: id)))
}

private func message(_ id: String, sender: String = "@alice:example.org") -> TimelineItem {
  event(
    id, sender: sender,
    content: .msgLike(
      content: .init(kind: .redacted, inReplyTo: nil, threadRoot: nil, threadSummary: nil)))
}

private func marker(_ id: String) -> TimelineItem {
  ProjectionTimelineItem(id: id, virtual: .readMarker)
}

private func stateGroups(_ projection: TimelineRowProjection) -> [[String]] {
  projection.rows.compactMap { row in
    guard case .state(let entries) = row else { return nil }
    return entries.map { $0.event.eventOrTransactionId.id }
  }
}

private struct ProjectionRowSnapshot: Equatable {
  let id: String
  let itemIDs: [String]
  let eventIDs: [String]
  let senders: [String]
  let timestamps: [UInt64]
}

private func snapshots(_ projection: TimelineRowProjection) -> [ProjectionRowSnapshot] {
  projection.rows.map { row in
    let items: [TimelineItem]
    let events: [EventTimelineItem]
    switch row {
    case .state(let entries):
      #expect(!entries.isEmpty)
      items = entries.map(\.item)
      events = entries.map(\.event)
    case .profile(let item, let event), .message(let item, let event, _):
      items = [item]
      events = [event]
    case .virtual(let item, _):
      items = [item]
      events = []
    case .typingIndicator:
      items = []
      events = []
    }
    return ProjectionRowSnapshot(
      id: row.id, itemIDs: items.map { $0.uniqueId().id },
      eventIDs: events.map { $0.eventOrTransactionId.id }, senders: events.map(\.sender),
      timestamps: events.map(\.timestamp))
  }
}

private func expectEquivalent(_ projection: TimelineRowProjection, to expected: [TimelineItem]) {
  #expect(projection.sourceItems.map { $0.uniqueId().id } == expected.map { $0.uniqueId().id })
  #expect(snapshots(projection) == snapshots(TimelineRowProjection(items: expected)))
  #expect(Set(projection.rows.map(\.id)).count == projection.rows.count)
  // UI rows are reversed, but entries within each state row remain in source order.
  let projectedItems = projection.rows.reversed().flatMap { row -> [TimelineItem] in
    switch row {
    case .state(let entries): entries.map(\.item)
    case .message(let item, _, _), .virtual(let item, _): [item]
    case .profile, .typingIndicator: []
    }
  }
  #expect(projectedItems.map { $0.uniqueId().id } == expected.map { $0.uniqueId().id })
}

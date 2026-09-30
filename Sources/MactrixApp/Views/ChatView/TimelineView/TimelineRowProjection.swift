import MatrixRustSDK

/// Maps contiguous SDK item ranges to ordered table rows. The current rules emit
/// one segment per item; a rule may later consume a run and emit a single row.
struct TimelineRowProjection {
  struct Segment {
    let sourceItems: [TimelineItem]
    let rows: [TimelineItemRowInfo]
  }

  struct Change {
    let oldIDs: [String]
    let changedIDs: Set<String>
  }

  private(set) var sourceItems: [TimelineItem]
  private var segments: [Segment]
  private(set) var rows: [TimelineItemRowInfo]

  init(items: [TimelineItem]) {
    sourceItems = items
    segments = Self.makeSegments(items, previous: nil)
    rows = Self.flatten(segments)
  }

  mutating func apply(_ diffs: [TimelineDiff]) -> Change {
    let oldIDs = rows.map(\.id)
    var changedIDs = Set<String>()

    for diff in diffs {
      switch diff {
      case .append(let values):
        replace(at: sourceItems.count, removing: 0, with: values, changedIDs: &changedIDs)
      case .clear:
        reset(to: [], changedIDs: &changedIDs)
      case .pushFront(let item):
        replace(at: 0, removing: 0, with: [item], changedIDs: &changedIDs)
      case .pushBack(let item):
        replace(at: sourceItems.count, removing: 0, with: [item], changedIDs: &changedIDs)
      case .popFront:
        replace(at: 0, removing: 1, with: [], changedIDs: &changedIDs)
      case .popBack:
        replace(at: sourceItems.count - 1, removing: 1, with: [], changedIDs: &changedIDs)
      case .insert(let index, let item):
        replace(at: Int(index), removing: 0, with: [item], changedIDs: &changedIDs)
      case .set(let index, let item):
        replace(at: Int(index), removing: 1, with: [item], changedIDs: &changedIDs)
      case .remove(let index):
        replace(at: Int(index), removing: 1, with: [], changedIDs: &changedIDs)
      case .truncate(let length):
        replace(
          at: Int(length), removing: sourceItems.count - Int(length), with: [],
          changedIDs: &changedIDs)
      case .reset(let values):
        reset(to: values, changedIDs: &changedIDs)
      }
    }

    rows = Self.flatten(segments)
    return Change(oldIDs: oldIDs, changedIDs: changedIDs)
  }

  private mutating func reset(to items: [TimelineItem], changedIDs: inout Set<String>) {
    changedIDs.formUnion(segments.flatMap { $0.rows.map(\.id) })
    sourceItems = items
    segments = Self.makeSegments(items, previous: nil)
    changedIDs.formUnion(segments.flatMap { $0.rows.map(\.id) })
  }

  private mutating func replace(
    at index: Int, removing count: Int, with items: [TimelineItem], changedIDs: inout Set<String>
  ) {
    guard count > 0 || !items.isEmpty else { return }

    // The predecessor determines whether the first changed message needs a
    // profile. The successor may gain or lose its own profile after the edit.
    let requestedStart = max(index - 1, 0)
    let requestedEnd = min(index + count + 1, sourceItems.count)
    let (segmentRange, sourceRange) = segmentWindow(containing: requestedStart..<requestedEnd)
    changedIDs.formUnion(segments[segmentRange].flatMap { $0.rows.map(\.id) })

    sourceItems.replaceSubrange(index..<index + count, with: items)
    let newEnd = sourceRange.upperBound + items.count - count
    let previous = sourceRange.lowerBound > 0 ? sourceItems[sourceRange.lowerBound - 1] : nil
    let replacement = Self.makeSegments(
      Array(sourceItems[sourceRange.lowerBound..<newEnd]), previous: previous
    )
    changedIDs.formUnion(replacement.flatMap { $0.rows.map(\.id) })
    segments.replaceSubrange(segmentRange, with: replacement)
  }

  /// Expands a source edit to whole segments. Future run based rules can
  /// extend this window to the nearest unchanged grouping boundaries.
  private func segmentWindow(containing requested: Range<Int>) -> (Range<Int>, Range<Int>) {
    var sourceOffset = 0
    var first: Int?
    var last = 0
    var lower = requested.lowerBound
    var upper = requested.upperBound
    for (index, segment) in segments.enumerated() {
      let end = sourceOffset + segment.sourceItems.count
      if first == nil, end > requested.lowerBound {
        first = index
        lower = sourceOffset
      }
      if sourceOffset < requested.upperBound {
        last = index + 1
        upper = end
      }
      sourceOffset = end
    }
    if let first { return (first..<last, lower..<upper) }
    return (segments.count..<segments.count, requested.lowerBound..<requested.upperBound)
  }

  private static func makeSegments(_ items: [TimelineItem], previous: TimelineItem?) -> [Segment] {
    var previousSender = sender(of: previous)
    return items.map { item in
      var projectedRows: [TimelineItemRowInfo] = []
      if let event = item.asEvent() {
        switch event.content {
        case .msgLike(let content):
          if previousSender != event.sender {
            projectedRows.append(.profile(item: item, event: event))
          }
          projectedRows.append(.message(item: item, event: event, content: content))
          previousSender = event.sender
        default:
          projectedRows.append(.state(item: item, event: event))
          previousSender = nil
        }
      } else if let virtual = item.asVirtual() {
        projectedRows.append(.virtual(item: item, virtual: virtual))
        previousSender = nil
      }
      return Segment(sourceItems: [item], rows: projectedRows)
    }
  }

  private static func sender(of item: TimelineItem?) -> String? {
    guard let event = item?.asEvent(), case .msgLike = event.content else { return nil }
    return event.sender
  }

  private static func flatten(_ segments: [Segment]) -> [TimelineItemRowInfo] {
    var result = segments.flatMap(\.rows)
    result.append(.typingIndicator)
    result.reverse()
    return result
  }
}

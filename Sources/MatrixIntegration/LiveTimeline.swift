import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

/// Delegate subscribed to by the `NSTimelineView` to update the focused timeline row.
@MainActor
public protocol LiveTimelineFocusDelegate: AnyObject {
  func focusTimelineEvent(id: EventOrTransactionId)
}

@MainActor
public protocol LiveTimelineDiffDelegate: AnyObject {
  func timelineDidApply(diffs: [TimelineDiff])
}

@MainActor @Observable
public final class LiveTimeline {
  public let room: LiveRoom
  public enum Focus: Hashable, Sendable {
    case live
    case thread(rootEventId: String)
    case event(eventId: String)
  }

  public let focus: Focus

  public var focusedThreadId: String? {
    guard case .thread(let id) = focus else { return nil }
    return id
  }

  public var focusedEventId: String? {
    guard case .event(let id) = focus else { return nil }
    return id
  }

  public var isLive: Bool { focus == .live }

  public var timeline: Timeline?

  @ObservationIgnored private var timelineHandle: TaskHandle?
  @ObservationIgnored private var paginateHandle: TaskHandle?
  @ObservationIgnored private var listenerTasks: [Task<Void, Never>] = []

  public var errorMessage: String?

  @ObservationIgnored public weak var focusDelegate: (any LiveTimelineFocusDelegate)?
  @ObservationIgnored public weak var diffDelegate: (any LiveTimelineDiffDelegate)?

  public private(set) var timelineItems: [TimelineItem] = []
  public private(set) var loadedReplyDetails: [String: InReplyToDetails] = [:]

  public private(set) var paginating: PaginationStatus = .idle(hitTimelineStart: false)
  public private(set) var hitTimelineStart: Bool = false
  public private(set) var hitTimelineEnd: Bool = false
  public private(set) var fetchingOlderMessages: Bool = false
  public private(set) var fetchingNewerMessages: Bool = false
  public private(set) var isConfigured: Bool = false
  public private(set) var paginationErrorMessage: String?

  public init(room: LiveRoom, focus: Focus = .live) {
    self.focus = focus
    self.room = room
    Task {
      do {
        try await configureTimeline()
      } catch {
        Logger.liveTimeline.error("failed to configure timeline: \(error)")
        self.errorMessage = error.localizedDescription
      }
    }
  }

  public convenience init(room: LiveRoom, focusThread threadId: String) {
    self.init(room: room, focus: .thread(rootEventId: threadId))
  }

  deinit {
    timelineHandle?.cancel()
    paginateHandle?.cancel()
    for task in listenerTasks { task.cancel() }
    Logger.liveTimeline.debug("Timeline deinit")
  }

  private func configureTimeline() async throws {
    Logger.liveTimeline.debug("configure timeline")

    let sdkFocus: TimelineFocus
    switch focus {
    case .live:
      sdkFocus = .live(hideThreadedEvents: true)
    case .thread(let rootEventId):
      sdkFocus = .thread(rootEventId: rootEventId)
    case .event(let eventId):
      sdkFocus = .event(
        eventId: eventId, numContextEvents: 50,
        threadMode: .automatic(hideThreadedEvents: true))
    }

    let config = TimelineConfiguration(
      focus: sdkFocus,
      filter: .all,
      internalIdPrefix: nil,
      dateDividerMode: .daily,
      trackReadReceipts: .allEvents,
      reportUtds: false
    )
    timeline = try await room.room.timelineWithConfiguration(configuration: config)

    await listenToTimelineChanges()

    isConfigured = true
    if isLive {
      do {
        try await listenToPaginationStatus()
      } catch {
        Logger.liveTimeline.error("Failed to listen to pagination status: \(error)")
        await fetchOlderMessages()
      }
    } else if focusedThreadId != nil {
      await fetchOlderMessages()
    }
  }

  private func listenToTimelineChanges() async {
    guard let timeline else { return }

    let listener = AsyncSDKListener<[TimelineDiff]>()
    timelineHandle = await timeline.addListener(listener: listener)

    listenerTasks.append(
      Task { [weak self] in
        for await diff in listener {
          guard let self, !Task.isCancelled else { break }
          updateTimeline(diff: diff)
        }
      })
  }

  private func listenToPaginationStatus() async throws {
    guard let timeline else { return }

    let listener = AsyncSDKListener<PaginationStatus>()
    // Focused timelines do not support this subscription.
    paginateHandle = try await timeline.subscribeToBackPaginationStatus(listener: listener)

    listenerTasks.append(
      Task { [weak self] in
        for await status in listener {
          guard let self, !Task.isCancelled else { break }

          Logger.liveTimeline.debug("updating timeline paginating: \(status.debugDescription)")
          paginating = status
          if case .idle(let hitStart) = status {
            hitTimelineStart = hitStart
          }

          if paginating == .idle(hitTimelineStart: false) && timelineItems.count < 100 {
            await fetchOlderMessages()
          }
        }
      })
  }

  public func fetchOlderMessages() async {
    guard !fetchingOlderMessages, !hitTimelineStart, !Task.isCancelled,
      let timeline
    else { return }

    fetchingOlderMessages = true
    paginationErrorMessage = nil
    defer { fetchingOlderMessages = false }

    do {
      hitTimelineStart = try await timeline.paginateBackwards(numEvents: 100)
    } catch is CancellationError {
      // Navigation can cancel a pending page request.
    } catch {
      paginationErrorMessage = error.localizedDescription
      Logger.liveTimeline.error("Failed to paginate backwards: \(error)")
    }
  }

  public func fetchNewerMessages() async {
    guard focusedEventId != nil, !fetchingNewerMessages, !hitTimelineEnd,
      !Task.isCancelled, let timeline
    else { return }

    fetchingNewerMessages = true
    paginationErrorMessage = nil
    defer { fetchingNewerMessages = false }

    do {
      hitTimelineEnd = try await timeline.paginateForwards(numEvents: 100)
    } catch is CancellationError {
      // Navigation can cancel a pending page request.
    } catch {
      paginationErrorMessage = error.localizedDescription
      Logger.liveTimeline.error("Failed to paginate forwards: \(error)")
    }
  }

  public func focusEvent(id eventId: EventOrTransactionId) {
    Logger.liveTimeline.info("focus event: \(eventId.id)")
    focusDelegate?.focusTimelineEvent(id: eventId)
  }
}

extension LiveTimeline {
  private func updateTimeline(diff: [TimelineDiff]) {
    for update in diff {
      switch update {
      case .append(let values):
        timelineItems.append(contentsOf: values)
      case .clear:
        timelineItems.removeAll()
      case .pushFront(let room):
        timelineItems.insert(room, at: 0)
      case .pushBack(let room):
        timelineItems.append(room)
      case .popFront:
        timelineItems.removeFirst()
      case .popBack:
        timelineItems.removeLast()
      case .insert(let index, let room):
        timelineItems.insert(room, at: Int(index))
      case .set(let index, let room):
        timelineItems[Int(index)] = room
      case .remove(let index):
        timelineItems.remove(at: Int(index))
      case .truncate(let length):
        timelineItems.removeSubrange(Int(length)..<timelineItems.count)
      case .reset(let values):
        timelineItems = values
      }
    }

    if timelineItems.first?.asVirtual() == .timelineStart {
      hitTimelineStart = true
    }

    diffDelegate?.timelineDidApply(diffs: diff)
    loadPendingReplyDetails()
  }

  private func loadPendingReplyDetails() {
    guard let sdkTimeline = timeline else { return }
    for item in timelineItems {
      guard let event = item.asEvent() else { continue }
      guard case .msgLike(content: let msgLike) = event.content else { continue }
      guard let inReplyTo = msgLike.inReplyTo else { continue }
      let eventId = inReplyTo.eventId()
      switch inReplyTo.event() {
      case .ready, .error: continue
      case .pending, .unavailable: break
      }
      guard loadedReplyDetails[eventId] == nil else { continue }
      Task { [weak self] in
        guard let self else { return }
        do {
          let details = try await sdkTimeline.loadReplyDetails(eventIdStr: eventId)
          self.loadedReplyDetails[eventId] = details
        } catch {
          Logger.liveTimeline.error("loadPendingReplyDetails: failed \(eventId): \(error)")
        }
      }
    }
  }
}

extension LiveTimeline: Equatable {
  public nonisolated static func == (lhs: LiveTimeline, rhs: LiveTimeline) -> Bool {
    lhs.room.id == rhs.room.id && lhs.focus == rhs.focus
  }
}

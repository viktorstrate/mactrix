import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI

@MainActor @Observable
public final class LiveTimeline {
    public let room: LiveRoom
    public let isThreadFocus: Bool

    public var timeline: Timeline?

    @ObservationIgnored private var timelineHandle: TaskHandle?
    @ObservationIgnored private var paginateHandle: TaskHandle?

    public var scrollPosition = ScrollPosition(idType: TimelineGroup.ID.self, edge: .bottom)
    public var errorMessage: String?

    public private(set) var focusedTimelineEventId: EventOrTransactionId?
    public private(set) var focusedTimelineGroupId: String?

    public var sendReplyTo: MatrixRustSDK.EventTimelineItem?

    @ObservationIgnored private var timelineItems: [TimelineItem] = []
    public private(set) var timelineGroups: TimelineGroups = .init()

    public private(set) var paginating: RoomPaginationStatus = .idle(hitTimelineStart: false)
    public private(set) var hitTimelineStart: Bool = false

    public init(room: LiveRoom) {
        self.isThreadFocus = false
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

    public init(room: LiveRoom, focusThread threadId: String) {
        self.isThreadFocus = true
        self.room = room
        Task {
            do {
                try await configureTimeline(threadId: threadId)
            } catch {
                Logger.liveTimeline.error("failed to configure timeline: \(error)")
                self.errorMessage = error.localizedDescription
            }
        }
    }

    deinit {
        Logger.liveTimeline.debug("Timeline deinit")
    }

    private func configureTimeline(threadId: String? = nil) async throws {
        Logger.liveTimeline.debug("configure timeline")
        
        let focus = if let threadId {
            TimelineFocus.thread(rootEventId: threadId)
        } else {
            TimelineFocus.live(hideThreadedEvents: true)
        }

        let config = TimelineConfiguration(
            focus: focus,
            filter: .all,
            internalIdPrefix: nil,
            dateDividerMode: .daily,
            trackReadReceipts: .allEvents,
            reportUtds: false
        )
        timeline = try await room.room.timelineWithConfiguration(configuration: config)

        await listenToTimelineChanges()

        // Only main timelines can subscibe to back pagination status
        if threadId == nil {
            do {
                try await listenToPaginationStatus()
            } catch {
                Logger.liveTimeline.error("Failed to listen to pagination status: \(error)")
            }
        }
    }

    private func listenToTimelineChanges() async {
        guard let timeline else { return }
        
        Logger.liveTimeline.info("Listen to timeline changes")

        let listener = AsyncSDKListener<[TimelineDiff]>()
        timelineHandle = await timeline.addListener(listener: listener)

        Task { [weak self] in
            for await diff in listener {
                guard let self else { break }
                Logger.liveTimeline.info("Timeline got change")
                updateTimeline(diff: diff)
            }
        }
    }

    private func listenToPaginationStatus() async throws {
        guard let timeline else { return }

        let listener = AsyncSDKListener<RoomPaginationStatus>()
        paginateHandle = try await timeline.subscribeToBackPaginationStatus(listener: listener)

        Task { [weak self] in
            for await status in listener {
                guard let self else { break }

                Logger.liveTimeline.debug("updating timeline paginating: \(status.debugDescription)")
                paginating = status
            }
        }
    }

    public func fetchOlderMessages() async throws {
        guard paginating == .idle(hitTimelineStart: false) else { return }
        _ = try await timeline?.paginateBackwards(numEvents: 100)
    }

    public func focusEvent(id eventId: EventOrTransactionId) {
        Logger.liveTimeline.info("focus event: \(eventId.id)")
        focusedTimelineEventId = eventId

        let group = timelineGroups.groups.first { group in
            switch group {
            case let .messages(messages, _, _):
                return messages.contains(where: { $0.event.eventOrTransactionId == eventId })
            case .stateChanges:
                return false
            case .virtual:
                return false
            }
        }
        focusedTimelineGroupId = group?.id

        if let focusedTimelineGroupId {
            withAnimation {
                scrollPosition.scrollTo(id: focusedTimelineGroupId)
            }
        }
    }
}

extension LiveTimeline {
    private func updateTimeline(diff: [TimelineDiff]) {
        let oldView = scrollPosition.viewID
        let oldEdge = scrollPosition.edge
        Logger.liveTimeline.trace("onUpdate old view \(oldView.debugDescription) \(oldEdge.debugDescription)")

        var updatedIds = Set<String>()

        for update in diff {
            switch update {
            case let .append(values):
                timelineItems.append(contentsOf: values)
                for value in values {
                    updatedIds.insert(value.uniqueId().id)
                }
            case .clear:
                timelineItems.removeAll()
            case let .pushFront(room):
                timelineItems.insert(room, at: 0)
                updatedIds.insert(room.uniqueId().id)
            case let .pushBack(room):
                timelineItems.append(room)
                updatedIds.insert(room.uniqueId().id)
            case .popFront:
                timelineItems.removeFirst()
            case .popBack:
                timelineItems.removeLast()
            case let .insert(index, room):
                timelineItems.insert(room, at: Int(index))
                updatedIds.insert(room.uniqueId().id)
            case let .set(index, room):
                timelineItems[Int(index)] = room
                updatedIds.insert(room.uniqueId().id)
            case let .remove(index):
                timelineItems.remove(at: Int(index))
            case let .truncate(length):
                timelineItems.removeSubrange(Int(length) ..< timelineItems.count)
            case let .reset(values: values):
                timelineItems = values
                for value in values {
                    updatedIds.insert(value.uniqueId().id)
                }
            }
        }

        timelineGroups.updateItems(items: timelineItems, updatedIds: updatedIds)

        if let oldEdge {
            scrollPosition.scrollTo(edge: oldEdge)
        } else if let oldView {
            scrollPosition.scrollTo(id: oldView, anchor: .top)
        }
    }
}

extension LiveTimeline: Equatable {
    public nonisolated static func == (lhs: LiveTimeline, rhs: LiveTimeline) -> Bool {
        lhs.room.id == rhs.room.id
    }
}

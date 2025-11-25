import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct TimelineItemView: View {
    let timeline: LiveTimeline
    let item: TimelineItem

    var body: some View {
        if let event = item.asEvent() {
            TimelineEventView(timeline: timeline, event: event)
        }
        if let virtual = item.asVirtual() {
            UI.VirtualItemView(item: virtual.asModel)
        }
    }
}

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var room: LiveRoom {
        timeline.room
    }

    @Bindable var timeline: LiveTimeline

    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    @State private var scrollNearTop: Bool = false
    @State private var scrollAtBottom: Bool = true
    @State private var latestVisibleEvent: MatrixRustSDK.TimelineItem? = nil
    @State private var latestMarkedReadEvent: MatrixRustSDK.TimelineItem? = nil

    func loadMoreMessages() {
        guard scrollNearTop else { return }
        guard timeline.paginating == .idle(hitTimelineStart: false) else { return }
        Logger.viewCycle.info("Reached top, fetching more messages...")

        Task {
            do {
                try await self.timeline.fetchOlderMessages()

//                if scrollNearTop {
//                    try await Task.sleep(for: .seconds(1))
//                    loadMoreMessages()
//                }
            } catch {
                Logger.viewCycle.error("failed to fetch more message for timeline: \(error)")
            }
        }
    }

    @ViewBuilder
    var timelineItemsView: some View {
        if let timelineItems = timeline.timelineItems {
            LazyVStack {
                ForEach(timelineItems) { item in
                    TimelineItemView(timeline: timeline, item: item)
                }
            }
            .scrollTargetLayout()
        } else {
            ProgressView()
        }
    }

    var timelineScrollView: some View {
        ScrollView {
            ProgressView("Loading more messages")
                .opacity(timeline.paginating == .paginating ? 1 : 0)

            timelineItemsView

            if let errorMessage = timeline.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                UI.UserTypingIndicator(names: room.typingUserIds)
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .scrollPosition($timeline.scrollPosition)
        .defaultScrollAnchor(.bottom)
        .safeAreaPadding(.bottom, 60) // chat input overlay
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.visibleRect.maxY - geo.containerSize.height < 400.0
        } action: { _, nearTop in
            Logger.viewCycle.info("scroll near top: \(nearTop)")
            scrollNearTop = nearTop
            if nearTop {
                loadMoreMessages()
            }
        }
        .onScrollTargetVisibilityChange(idType: TimelineItem.ID.self) { visibleTimelineItemIds in
            guard let timelineItems = timeline.timelineItems else { return }
            var latestEvent: MatrixRustSDK.TimelineItem? = nil

            for id in visibleTimelineItemIds {
                guard let item = timelineItems.first(where: { $0.id == id }) else {
                    continue
                }

                guard let event = item.asEvent() else { continue }

                if let latest = latestEvent {
                    if latest.asEvent()!.date < event.date {
                        latestEvent = item
                    }
                } else {
                    latestEvent = item
                }
            }

            latestVisibleEvent = latestEvent
        }
    }

    var toolbarSubtitle: String {
        guard let topic = room.topic() else { return "" }
        let firstLine = topic.split(separator: "\n").first ?? ""
        return String(firstLine)
    }

    @ViewBuilder
    var joinedRoom: some View {
        timelineScrollView
            .overlay(alignment: .bottom) {
                ChatInputView(room: room, timeline: timeline.timeline, replyTo: $timeline.sendReplyTo)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.displayName() ?? "Unknown room")
            .navigationSubtitle(toolbarSubtitle)
            .frame(minWidth: 250, minHeight: 200)
            .onChange(of: timeline.timelineItems) { _, _ in
                if timeline.scrollPosition.edge == .bottom {
                    Task {
                        await Task.yield()
                        timeline.scrollPosition.scrollTo(edge: .bottom)
                    }
                }
            }
            .task(id: latestVisibleEvent) {
                do {
                    guard let latest = latestVisibleEvent else { return }
                    guard latest != latestMarkedReadEvent else { return }
                    try await Task.sleep(for: .seconds(2))
                    if latest.uniqueId() == latestVisibleEvent?.uniqueId() {
                        guard let event = latest.asEvent() else {
                            Logger.viewCycle.fault("unreachable: latest should be event")
                            return
                        }

                        guard let timelineItems = timeline.timelineItems else { return }

                        // there doesn't seem to be an API to mark which event is the latest fully read.
                        // instead only send the receipt when the latest message has been read
                        let isLaterEvents = timelineItems.contains(where: {
                            if let e = $0.asEvent() { e.date > event.date } else { false }
                        })

                        if !isLaterEvents {
                            try await timeline.timeline?.markAsRead(receiptType: .fullyRead)
                            Logger.viewCycle.info("latest event marked as read: \(latest.id)")
                            self.latestMarkedReadEvent = latest
                        }
                    }
                } catch { /* sleep cancelled */ }
            }
    }

    @ViewBuilder
    var invitedRoom: some View {
        Text("Invited to room")
            .font(.title)

        Button("Accept Invite") {
            Task {
                do {
                    try await room.join()
                } catch {
                    Logger.viewCycle.error("failed to join: \(error)")
                }
            }
        }

        Button("Reject Invite") {
            Task {
                do {
                    try await room.leave()
                    try await room.forget()
                } catch {
                    Logger.viewCycle.error("failed to leave room: \(error)")
                }
            }
        }
    }

    var body: some View {
        switch room.membership() {
        case .joined:
            joinedRoom
        case .invited:
            invitedRoom
        case .left:
            Text("You have left this room")
        case .knocked:
            Text("You have knocked to ask to join this room")
        case .banned:
            Text("You are banned from this room")
        }
    }
}

import MatrixRustSDK
import Models
import SwiftUI
import UI

struct TimelineItemView: View {
    let timeline: LiveTimeline?
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

    let room: LiveRoom
    @State private var timeline: LiveTimeline? = nil

    @State private var errorMessage: String? = nil

    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var scrollNearTop: Bool = false
    @State private var scrollAtBottom: Bool = true
    @State private var latestVisibleEvent: MatrixRustSDK.TimelineItem? = nil
    @State private var latestMarkedReadEvent: MatrixRustSDK.TimelineItem? = nil

    func loadMoreMessages() {
        guard timeline?.paginating == .idle(hitTimelineStart: false) else { return }
        print("Reached top, fetching more messages...")

        Task {
            do {
                try await self.timeline?.fetchOlderMessages()

                if scrollNearTop {
                    loadMoreMessages()
                }
            } catch {
                print("failed to fetch more message for timeline: \(error)")
            }
        }
    }

    @ViewBuilder
    var timelineItemsView: some View {
        if let timelineItems = timeline?.timelineItems {
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
                .opacity(timeline?.paginating == .paginating ? 1 : 0)

            timelineItemsView

            if let errorMessage = errorMessage {
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
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .contentMargins(.bottom, 10)
        .contentMargins(.top, 20)
        .safeAreaPadding(.bottom, 60)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.visibleRect.maxY - geo.containerSize.height < 400.0
        } action: { _, nearTop in
            scrollNearTop = nearTop
            if nearTop {
                loadMoreMessages()
            }
        }
        .onScrollTargetVisibilityChange(idType: TimelineItem.ID.self) { visibleTimelineItemIds in
            var latestEvent: MatrixRustSDK.TimelineItem? = nil

            for id in visibleTimelineItemIds {
                guard let item = timeline?.timelineItems.first(where: { $0.id == id }) else {
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

    @ViewBuilder
    var joinedRoom: some View {
        timelineScrollView
            .overlay(alignment: .bottom) {
                ChatInputView(room: room, timeline: timeline?.timeline)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.displayName() ?? "Unknown room")
            .navigationSubtitle(room.topic() ?? "")
            .frame(minWidth: 250, minHeight: 200)
            .task(id: room) {
                do {
                    self.timeline = try await LiveTimeline(room: room)
                } catch {
                    print("loading timeline failed: \(error)")
                    self.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: timeline?.timelineItems) { _, _ in
                if scrollPosition.edge == .bottom {
                    Task {
                        await Task.yield()
                        scrollPosition.scrollTo(edge: .bottom)
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
                            print("unreachable: latest should be event")
                            return
                        }

                        guard let timeline else { return }

                        // there doesn't seem to be an API to mark which event is the latest fully read.
                        // instead only send the receipt when the latest message has been read
                        let isLaterEvents = timeline.timelineItems.contains(where: {
                            if let e = $0.asEvent() { e.date > event.date } else { false }
                        })

                        if !isLaterEvents {
                            try await timeline.timeline.markAsRead(receiptType: .fullyRead)
                            print("latest event marked as read: \(latest.id)")
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
                    print("failed to join: \(error)")
                }
            }
        }

        Button("Reject Invite") {
            Task {
                do {
                    try await room.leave()
                    try await room.forget()
                } catch {
                    print("failed to leave room: \(error)")
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

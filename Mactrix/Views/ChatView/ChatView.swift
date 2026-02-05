import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct TimelineGroupView: View {
    let timeline: LiveTimeline
    let timelineGroup: TimelineGroup

    var body: some View {
        switch timelineGroup {
        case .messages(let messages, _, _):
            ForEach(messages) { message in
                ChatMessageView(timeline: timeline, event: message.event, msg: message.content, includeProfileHeader: message.id == messages.first?.id)
            }
        case .stateChanges(let events, _, _):
            TimelineStateEventsView(timeline: timeline, events: events)
        case .virtual(let item, _, _):
            UI.VirtualItemView(item: item.asModel)
        }
    }
}

struct TimelineItemsView: View {
    let timeline: LiveTimeline

    var body: some View {
        if !timeline.timelineGroups.groups.isEmpty {
            LazyVStack {
                ForEach(timeline.timelineGroups.groups) { item in
                    TimelineGroupView(timeline: timeline, timelineGroup: item)
                }
            }
            .scrollTargetLayout()
        } else {
            ProgressView()
        }
    }
}

struct ChatTimelineScrollView: View {
    @Bindable var timeline: LiveTimeline

    @State private var scrollNearTop: Bool = false

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

    var body: some View {
        ScrollView {
            ProgressView("Loading more messages")
                .opacity(timeline.paginating == .paginating ? 1 : 0)

            TimelineItemsView(timeline: timeline)

            if let errorMessage = timeline.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                UI.UserTypingIndicator(names: timeline.room.typingUserIds)
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .scrollPosition($timeline.scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.visibleRect.maxY - geo.containerSize.height < 400.0
        } action: { _, nearTop in
            Logger.viewCycle.info("scroll near top: \(nearTop)")
            scrollNearTop = nearTop
            if nearTop {
                loadMoreMessages()
            }
        }
        .task(id: timeline.timelineGroups) {
            do {
                try await Task.sleep(for: .seconds(1))

                Logger.viewCycle.debug("Mark room as read")
                try await timeline.timeline?.markAsRead(receiptType: .read)
            } catch is CancellationError {
                /* sleep cancelled */
            } catch {
                Logger.viewCycle.error("failed to send timeline read receipt: \(error)")
            }
        }
    }
}

struct ChatJoinedRoom: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Bindable var timeline: LiveTimeline

    var room: LiveRoom {
        timeline.room
    }

    @State private var inputHeight: CGFloat?
    @FocusState private var inputFocused: Bool

    var toolbarSubtitle: String {
        guard let topic = room.room.topic() else { return "" }
        let firstLine = topic.split(whereSeparator: \.isNewline).first ?? ""
        return String(firstLine)
    }

    var body: some View {
        ChatTimelineScrollView(timeline: timeline)
            .safeAreaPadding(.bottom, inputHeight ?? 60) // chat input overlay
            .overlay(alignment: .bottom) {
                ChatInputView(room: room.room, timeline: timeline, replyTo: $timeline.sendReplyTo, height: $inputHeight, focusState: $inputFocused)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.room.displayName() ?? "Unknown room")
            .navigationSubtitle(toolbarSubtitle)
            .frame(minWidth: 250, minHeight: 200)
            .onAppear {
                // Delay focus slightly to ensure view is fully rendered
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    inputFocused = true
                }
            }
            .onChange(of: windowState.shouldFocusInput) { _, shouldFocus in
                if shouldFocus {
                    // Delay focus to ensure the new room view is rendered
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        inputFocused = true
                        windowState.shouldFocusInput = false
                    }
                }
            }
            .task {
                do {
                    try await Task.sleep(for: .seconds(2))
                    try await appState.matrixClient?.client.trackRecentlyVisitedRoom(room: timeline.room.id)
                    Logger.viewCycle.debug("marked room as recently visited: \(timeline.room.id)")
                } catch is CancellationError {
                    /* sleep cancelled */
                } catch {
                    Logger.viewCycle.error("failed to mark room as recently visited: \(error)")
                }
            }
            .onDisappear {
                Task {
                    guard let timeline = timeline.timeline else { return }
                    do {
                        Logger.viewCycle.info("Unfocusing room, marking it as read")
                        try await timeline.markAsRead(receiptType: .fullyRead)
                    } catch {
                        Logger.viewCycle.error("Failed to mark room as read: \(error)")
                    }
                }
            }
    }
}

struct ChatView: View {
    @Bindable var timeline: LiveTimeline

    var room: LiveRoom {
        timeline.room
    }

    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    @ViewBuilder
    var invitedRoom: some View {
        Text("Invited to room")
            .font(.title)

        Button("Accept Invite") {
            Task {
                do {
                    try await room.room.join()
                } catch {
                    Logger.viewCycle.error("failed to join: \(error)")
                }
            }
        }

        Button("Reject Invite") {
            Task {
                do {
                    try await room.room.leave()
                    try await room.room.forget()
                } catch {
                    Logger.viewCycle.error("failed to leave room: \(error)")
                }
            }
        }
    }

    var body: some View {
        switch room.room.membership() {
        case .joined:
            ChatJoinedRoom(timeline: timeline)
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

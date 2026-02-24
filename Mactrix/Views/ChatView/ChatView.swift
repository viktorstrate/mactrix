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

struct ChatJoinedRoom: View {
    @Environment(AppState.self) private var appState
    @Bindable var timeline: LiveTimeline

    var room: LiveRoom {
        timeline.room
    }

    @State private var inputHeight: CGFloat?

    var toolbarSubtitle: String {
        guard let topic = room.room.topic() else { return "" }
        let firstLine = topic.split(whereSeparator: \.isNewline).first ?? ""
        return String(firstLine)
    }

    var body: some View {
        TimelineViewRepresentable(timeline: timeline, items: timeline.timelineItems)
            .safeAreaPadding(.bottom, inputHeight ?? 60) // chat input overlay
            .overlay(alignment: .bottom) {
                ChatInputView(room: room.room, timeline: timeline, replyTo: $timeline.sendReplyTo, height: $inputHeight)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.room.displayName() ?? "Unknown room")
            .navigationSubtitle(toolbarSubtitle)
            .frame(minWidth: 250, minHeight: 200)
            .task(priority: .background) {
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
            .task(id: timeline.timelineItems.count, priority: .background) {
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

import MatrixRustSDK
import MatrixProtocols
import OSLog
import SwiftUI
import MactrixUI
import MatrixIntegration
import MactrixApp

struct RoomPinRow: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    let eventId: String

    @State private var event: MatrixRustSDK.EventTimelineItem?

    @ViewBuilder
    var content: some View {
        if let event {
            VStack {
                Text(event.sender).bold()
                Text(event.content.userInterfaceText)
            }
        } else {
            Text("Loading message...")
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        content
            .task(id: eventId) {
                do {
                    event = try await timeline.timeline?.getEventTimelineItemByEventId(eventId: eventId)
                } catch {
                    Logger.viewCycle.error("failed to fetch details for pinned event \(error)")
                }
            }
    }
}

struct InspectorRoomPins: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State var pinnedMessages: [String] = []
    @State var selectedId: String?

    var timeline: LiveTimeline? {
        guard case let .joinedRoom(timeline: timeline) = windowState.selectedScreen else {
            return nil
        }

        return timeline
    }

    var pinnedEventIds: [String] {
        guard let timeline, let roomInfo = timeline.room.roomInfo else {
            return []
        }
        // TODO: Use a pinned timeline instead
        return roomInfo.pinnedEventIds
    }

    var body: some View {
        if let timeline, !pinnedEventIds.isEmpty {
            List(pinnedEventIds, id: \.self, selection: $selectedId) { eventId in
                RoomPinRow(timeline: timeline, eventId: eventId)
            }
            .onChange(of: selectedId) {
                guard let selectedId else { return }
                windowState.focusMessage(eventId: selectedId)
            }
        } else {
            ContentUnavailableView("No pinned messages", systemImage: "pin.circle")
        }
    }
}

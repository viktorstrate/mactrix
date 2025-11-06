import SwiftUI
import MatrixRustSDK

struct TimelineItemView: View {
    
    let event: EventTimelineItem
    
    var body: some View {
        switch event.content {
        case .msgLike(content: let content):
            ChatMessageView(event: event, msg: content)
        case .callInvite:
            GenericEventView(name: "Call invite")
        case .rtcNotification:
            GenericEventView(name: "Rtc notification")
        case .roomMembership(userId: _, userDisplayName: _, change: _, reason: _):
            GenericEventView(name: "Room membership")
        case .profileChange(displayName: _, prevDisplayName: _, avatarUrl: _, prevAvatarUrl: _):
            GenericEventView(name: "Profile change")
        case let .state(stateKey: stateKey, content: content):
            StateEventView(event: event, stateKey: stateKey, state: content)
        case .failedToParseMessageLike(eventType: _, error: let error):
            GenericEventView(name: "Failed to parse message like: \(error)")
        case .failedToParseState(eventType: _, stateKey: _, error: let error):
            GenericEventView(name: "Failed to parse state: \(error)")
        }
    }
}

#Preview {
    TimelineItemView(event: .previewTextItem)
}

struct ChatView: View {
    @Environment(AppState.self) private var appState
    
    let room: Room
    @State private var timeline: RoomTimeline? = nil
    
    @State private var errorMessage: String? = nil
    
    @State private var scrollPosition: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.vertical]) {
                if let timelineItems = timeline?.timelineItems {
                            LazyVStack {
                                    ForEach(timelineItems) { item in
                                        if let event = item.asEvent() {
                                            TimelineItemView(event: event)
                                                .id(item.id)
                                        }
                                        if let virtual = item.asVirtual() {
                                            VirtualItemView(item: virtual)
                                                .id(item.id)
                                        }
                                    }
                            }
                            .scrollTargetLayout()
                } else {
                    ProgressView()
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                }
                
            }
            .scrollPosition(id: $scrollPosition, anchor: .bottom)
            .safeAreaPadding(.bottom, 10)
            .safeAreaPadding(.top, 20)
            .scrollContentBackground(.hidden)
            .defaultScrollAnchor(.bottom)
            
            ChatInputView(room: room, timeline: timeline?.timeline)
        }
        .task(id: room) {
            do {
                self.timeline = try await RoomTimeline(room: room)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: self.timeline?.timelineItems.count ?? 0) { prev, now in
            if now > 0 {
                Task {
                    if prev == 0 { // disable animation on first load
                        self.scrollPosition = self.timeline?.timelineItems.last?.id
                        await Task.yield()
                        self.scrollPosition = self.timeline?.timelineItems.last?.id
                    } else {
                        await Task.yield()
                        withAnimation {
                            self.scrollPosition = self.timeline?.timelineItems.last?.id
                        }
                    }
                }
            }
        }
    }
}

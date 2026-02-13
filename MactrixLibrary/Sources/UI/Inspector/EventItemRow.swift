import Models
import SwiftUI

public struct EventItemRow<Event: EventTimelineItem>: View {
    let event: Event

    public var body: some View {
        VStack {
            Text(event.sender)
        }
    }
}

#Preview {
    List {
        EventItemRow(event: MockEventTimelineItem())
        EventItemRow(event: MockEventTimelineItem())
        EventItemRow(event: MockEventTimelineItem())
    }
}

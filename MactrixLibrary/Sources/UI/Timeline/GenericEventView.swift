import Models
import SwiftUI

public struct GenericEventView: View {
    let event: EventTimelineItem
    let name: String

    @State private var hover = false

    public init(event: EventTimelineItem, name: String) {
        self.event = event
        self.name = name
    }

    public var body: some View {
        HStack(spacing: 0) {
            MessageTimestampView(date: event.date, hover: hover)
            Text("\(Text(event.sender).bold()): \(Text(name).italic())")
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 10)
        .onHover { hover in
            self.hover = hover
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        GenericEventView(event: MockEventTimelineItem(), name: "Test Event")
        GenericEventView(event: MockEventTimelineItem(), name: "Test Event")
        GenericEventView(event: MockEventTimelineItem(), name: "Test Event")
    }
}

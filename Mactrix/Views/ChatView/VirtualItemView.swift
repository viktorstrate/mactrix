import SwiftUI
import MatrixRustSDK

struct VirtualItemView: View {
    let item: VirtualTimelineItem
    
    var body: some View {
        switch item {
        case .dateDivider(let ts):
            Text("Date: \(ts.date.formatted())")
        case .readMarker:
            Text("Read Marker")
        case .timelineStart:
            Text("Start of conversation")
        }
    }
}

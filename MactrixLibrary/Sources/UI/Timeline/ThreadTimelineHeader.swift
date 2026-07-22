import SwiftUI

public struct ThreadTimelineHeader: View {
    let dismiss: () -> Void

    public init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Button(action: dismiss) {
                    Label("Close thread", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)

                Text("Thread")
                    .font(.headline)
            }
            .padding(10)
            Divider()
        }
        .background(.thinMaterial)
    }
}

#Preview {
    VStack(spacing: 0) {
        ThreadTimelineHeader {}
        Text("Body")
            .frame(maxWidth: .infinity, maxHeight: 40)
            .background(.white)
    }
}

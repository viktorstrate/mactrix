import Models
import SwiftUI

struct MessageReactionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(
            action: { configuration.isOn.toggle() },
            label: {
                configuration.label
                    .background(
                        configuration.isOn ?
                            Color.blue.quaternary : Color.gray.quaternary
                    )
            }
        )
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(configuration.isOn ? Color.blue : Color.gray)
        }
    }
}

public struct MessageReactionView<Reaction: Models.Reaction>: View {
    let reaction: Reaction
    let active: Binding<Bool>

    @FocusState private var isFocused: Bool

    public init(reaction: Reaction, active: Binding<Bool>) {
        self.reaction = reaction
        self.active = active
    }

    public var body: some View {
        Toggle(isOn: active, label: {
            HStack(spacing: 0) {
                Text(reaction.key)
                Text("\(reaction.senders.count)")
                    .padding(.horizontal, 6)
            }
            .padding(4)
        })
        .toggleStyle(MessageReactionToggleStyle())
    }
}

#Preview {
    @Previewable @State var active = false
    MessageReactionView(reaction: MockReaction(), active: $active)
        .padding()
}

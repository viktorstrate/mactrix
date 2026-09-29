import SwiftUI

struct SectionAction<Content: View>: View {
    let title: LocalizedStringKey
    let systemIcon: String
    let action: () -> Void
    let content: () -> Content

    @State private var isHovering = false

    init(
        title: LocalizedStringKey,
        systemIcon: String,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemIcon = systemIcon
        self.action = action
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Add room", systemImage: systemIcon, action: action)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)
                    .padding(.trailing, 2)
            }
            .onHover { hover in
                self.isHovering = hover
            }
        }
    }
}

#Preview {
    List {
        SectionAction(title: "Section name", systemIcon: "plus.circle", action: {}) {
            Text("Content")
            Text("Content")
            Text("Content")
        }
    }
    .listStyle(.sidebar)
    .frame(width: 200, height: 200)
}

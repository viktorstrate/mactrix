import SwiftUI

struct ErrorPopover: View {
    let error: Error
    
    var body: some View {
        VStack(alignment: .leading) {
            Label("Failed to join room", systemImage: "exclamationmark.triangle")
                .textSelection(.enabled)
                .font(.headline)
            Text(error.localizedDescription)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .frame(width: 400)
        .padding()
    }
}

struct MockError: LocalizedError {
    var errorDescription: String? {
        "Something failed, this is a long and detailed explaination of the error."
    }
}

#Preview {
    Text("Hello")
        .popover(isPresented: .constant(true)) {
            ErrorPopover(error: MockError())
        }
}

public struct RoomRow: View {
    let title: String
    let avatarUrl: String?
    let placeholderImageName: String
    let imageLoader: ImageLoader?
    let joinRoom: (() async throws -> Void)?
    
    @State private var joining: Bool = false
    @State private var error: Error? = nil
    @State private var isErrorVisible: Bool = false

    public init(title: String, avatarUrl: String?, imageLoader: ImageLoader?, joinRoom: (() async throws -> Void)?, placeholderImageName: String = "number") {
        self.title = title
        self.avatarUrl = avatarUrl
        self.imageLoader = imageLoader
        self.placeholderImageName = placeholderImageName
        self.joinRoom = joinRoom
    }
    
    var label: some View {
        Label(
            title: { Text(title) },
            icon: {
                UI.AvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
                    Image(systemName: placeholderImageName)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        )
    }
    
    public var body: some View {
        Group {
            if joinRoom != nil {
                HStack {
                    label
                    Spacer()
                    if let error {
                        Button {
                            isErrorVisible.toggle()
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isErrorVisible) {
                            ErrorPopover(error: error)
                        }
                    } else if joining {
                        ProgressView().scaleEffect(0.4)
                    } else {
                        Button("Join") {
                            joining = true
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            } else {
                label
            }
        }
        .listItemTint(.gray)
        .task(id: joining) {
            guard joining else { return }
            guard let joinRoom else { return }
            
            do {
                try await joinRoom()
            } catch {
                print("failed to join room \(error)")
                self.error = error
                self.isErrorVisible = true
            }
            
            joining = false
        }
    }
}

#Preview {
    List {
        Section("Rooms") {
            RoomRow(
                title: "Room row 1",
                avatarUrl: nil,
                imageLoader: nil,
                joinRoom: nil,
                placeholderImageName: "number"
            )
            
            RoomRow(
                title: "Room row 2",
                avatarUrl: nil,
                imageLoader: nil,
                joinRoom: nil,
                placeholderImageName: "number"
            )
            
            RoomRow(
                title: "Room row 3",
                avatarUrl: nil,
                imageLoader: nil,
                joinRoom: {},
                placeholderImageName: "number"
            )
        }
    }
    .listStyle(.sidebar)
    .frame(width: 200)
}

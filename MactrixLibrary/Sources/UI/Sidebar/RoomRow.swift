import Models
import OSLog
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
    ErrorPopover(error: MockError())
    /* Text("Hello")
     .popover(isPresented: .constant(true)) {
         ErrorPopover(error: MockError())
     } */
}

public struct RoomRow: View {
    let title: String
    let avatarUrl: String?
    let roomInfo: RoomInfo?
    let imageLoader: ImageLoader?
    let joinRoom: (() async throws -> Void)?

    @State private var joining: Bool = false
    @State private var error: Error? = nil
    @State private var isErrorVisible: Bool = false
    @ScaledMetric(relativeTo: .body) private var roomAvatarSize: CGFloat = 22.0

    public init(title: String, avatarUrl: String?, roomInfo: RoomInfo?, imageLoader: ImageLoader?, joinRoom: (() async throws -> Void)?) {
        self.title = title
        self.avatarUrl = avatarUrl
        self.roomInfo = roomInfo
        self.imageLoader = imageLoader
        self.joinRoom = joinRoom
    }

    var placeholderImageName: String {
        if roomInfo?.isSpace == true {
            "network"
        } else if roomInfo?.isDirect == true {
            "person.fill"
        } else {
            "number"
        }
    }

    var label: some View {
        Label(
            title: {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            },
            icon: {
                UI.AvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.clear)
                        .overlay {
                            Image(systemName: placeholderImageName)
                        }
                }
                .frame(width: roomAvatarSize, height: roomAvatarSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        )
        .fontWeight(isUnread ? .bold : .regular)
        .help(title)
    }

    var badgeProminence: BadgeProminence {
        guard let roomInfo else { return .standard }
        return roomInfo.numUnreadNotifications > 0 || roomInfo.numUnreadMentions > 0 ? .increased : .standard
    }

    var notifications: Int {
        guard let roomInfo else { return 0 }

        let highlightMessages = Int(max(
            roomInfo.numUnreadNotifications,
            roomInfo.numUnreadMentions
        ))

        if highlightMessages > 0 {
            return highlightMessages
        } else {
            return Int(roomInfo.numUnreadMessages)
        }
    }

    var isUnread: Bool {
        return notifications > 0 || roomInfo?.isMarkedUnread == true
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
        .badge(notifications)
        .badgeProminence(badgeProminence)
        .listItemTint(.gray)
        .task(id: joining) {
            guard joining else { return }
            guard let joinRoom else { return }

            do {
                try await joinRoom()
            } catch {
                Logger.viewCycle.error("failed to join room \(error)")
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
                roomInfo: nil,
                imageLoader: nil,
                joinRoom: nil
            )

            RoomRow(
                title: "Room row 2",
                avatarUrl: nil,
                roomInfo: nil,
                imageLoader: nil,
                joinRoom: nil
            )

            RoomRow(
                title: "Room row 3",
                avatarUrl: nil,
                roomInfo: nil,
                imageLoader: nil,
                joinRoom: {}
            )
        }
    }
    .listStyle(.sidebar)
    .frame(width: 200)
}

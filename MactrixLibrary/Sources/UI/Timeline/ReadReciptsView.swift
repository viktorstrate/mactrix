import Models
import SwiftUI

struct ReadReciptsView<RoomMember: Models.RoomMember>: View {
    let receipts: [String: Receipt]
    let imageLoader: ImageLoader?
    let roomMembers: [RoomMember]

    var users: [String] {
        receipts
            .sorted { a, b in
                let a = (a.value.timestamp ?? Date(timeIntervalSince1970: 0))
                let b = (b.value.timestamp ?? Date(timeIntervalSince1970: 0))
                return a < b
            }
            .map { key, _ in key }
    }

    @ViewBuilder
    func avatarImage(forUserId userId: String) -> some View {
        let user = roomMembers.first(where: { $0.id == userId })

        if let user {
            AvatarImage(userProfile: user, imageLoader: imageLoader)
        } else {
            AvatarImage(avatarUrl: nil, imageLoader: imageLoader)
        }
    }

    func userDisplayName(forUserId userId: String) -> String {
        let user = roomMembers.first(where: { $0.id == userId })
        return user?.displayName ?? userId
    }

    var body: some View {
        HStack(spacing: -2) {
            ForEach(users, id: \.self) { userId in
                avatarImage(forUserId: userId)
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
                    .background(
                        Circle().stroke(Color(NSColor.controlBackgroundColor), lineWidth: 3)
                    )
                    .help("Read by \(userDisplayName(forUserId: userId))")
            }
        }
    }
}

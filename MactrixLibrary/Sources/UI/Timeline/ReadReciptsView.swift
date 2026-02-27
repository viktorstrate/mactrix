import Models
import SwiftUI

struct ReadReciptsView<RoomMember: Models.RoomMember>: View {
    let receipts: [String: Receipt]
    let imageLoader: ImageLoader?
    let roomMembers: [RoomMember]

    private let truncatedAvatarLimit = 3
    private let fullAvatarLimit = 4

    var users: [String] {
        receipts
            .sorted { a, b in
                let a = (a.value.timestamp ?? Date(timeIntervalSince1970: 0))
                let b = (b.value.timestamp ?? Date(timeIntervalSince1970: 0))
                return a < b
            }
            .map { key, _ in key }
    }

    var visibleUsers: [String] {
        let shouldTruncate = users.count > fullAvatarLimit
        let visibleAvatarLimit = shouldTruncate ? truncatedAvatarLimit : fullAvatarLimit
        return Array(users.suffix(visibleAvatarLimit))
    }

    var hiddenCount: Int {
        users.count - visibleUsers.count
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

    func overflowTooltip(forHiddenUsers hiddenUsers: [String]) -> String {
        let names = hiddenUsers.map { userDisplayName(forUserId: $0) }

        switch names.count {
        case 1:
            return "Read by \(names[0])"
        case 2:
            return "Read by \(names[0]) and \(names[1])"
        case 3:
            return "Read by \(names[0]), \(names[1]), and 1 other"
        default:
            return "Read by \(names[0]), \(names[1]), and \(names.count - 2) others"
        }
    }

    var body: some View {
        HStack(spacing: -2) {
            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
                    .help(overflowTooltip(forHiddenUsers: Array(users.dropLast(visibleUsers.count))))
                    .padding(.trailing, 4)
            }
            ForEach(visibleUsers, id: \.self) { userId in
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

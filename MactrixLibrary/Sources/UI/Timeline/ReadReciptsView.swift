import Models
import SwiftUI

struct ReadReciptsView<RoomMember: Models.RoomMember>: View {
    let receipts: [String: Receipt]
    let imageLoader: ImageLoader?
    let roomMembers: [RoomMember]

    private let truncatedAvatarLimit = 3
    private let fullAvatarLimit = 4
    @State private var showPopover: Bool = false

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

    var popoverUsers: [String] {
        users.reversed()
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

    func readByTooltip(forUsers userIds: [String]) -> String {
        let names = userIds.map { userDisplayName(forUserId: $0) }

        switch names.count {
        case 0:
            return ""
        case 1:
            return "Read by \(names[0])"
        case 2:
            return "Read by \(names[0]) and \(names[1])"
        case 3:
            return "Read by \(names[0]), \(names[1]), and \(names[2])"
        default:
            return "Read by \(names[0]), \(names[1]), and \(names.count - 2) others"
        }
    }

    func formattedTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    var popoverHeader: String {
        users.count == 1 ? "Read by 1 person" : "Read by \(users.count) people"
    }

    @ViewBuilder
    var readReceiptsPopover: some View {
        VStack(alignment: .leading) {
            Text(popoverHeader)
                .font(.headline)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(popoverUsers, id: \.self) { userId in
                        HStack(spacing: 10) {
                            avatarImage(forUserId: userId)
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(userDisplayName(forUserId: userId))
                                    .font(.body)
                                    .lineLimit(1)

                                if let timestamp = receipts[userId]?.timestamp {
                                    Text(formattedTimestamp(timestamp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 200)
        .frame(maxHeight: 250)
        .padding()
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: -2) {
                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                ForEach(visibleUsers, id: \.self) { userId in
                    avatarImage(forUserId: userId)
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
                        .background(
                            Circle().stroke(Color(NSColor.controlBackgroundColor), lineWidth: 3)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(readByTooltip(forUsers: users))
        .popover(isPresented: $showPopover) {
            readReceiptsPopover
        }
    }
}

import Models
import OSLog
import SwiftUI

struct RoomInspectorMemberRow<RoomMember: Models.RoomMember>: View {
    let member: RoomMember
    let imageLoader: ImageLoader?

    var body: some View {
        UserProfileRow(profile: member, imageLoader: imageLoader)
    }
}

public struct RoomInspectorView<Room: Models.Room, RoomMember: Models.RoomMember>: View {
    let room: Room
    let members: [RoomMember]

    let roomInfo: RoomInfo?
    let imageLoader: ImageLoader?

    @Binding var inspectorVisible: Bool

    public init(room: Room, members: [RoomMember], roomInfo: RoomInfo?, imageLoader: ImageLoader?, inspectorVisible: Binding<Bool>) {
        self.room = room
        self.members = members
        self.imageLoader = imageLoader
        self.roomInfo = roomInfo
        _inspectorVisible = inspectorVisible
    }

    @ViewBuilder
    func userSection(title: LocalizedStringResource, allMembers: [RoomMember], withRole role: RoomMemberRole) -> some View {
        let roleMembers = allMembers.filter { $0.roleForPowerLevel == role }
        Section("\(title) (\(roleMembers.count))") {
            ForEach(roleMembers) { member in
                RoomInspectorMemberRow(member: member, imageLoader: imageLoader)
            }
        }
    }

    @ViewBuilder
    var header: some View {
        VStack(alignment: .center, spacing: 20) {
            VStack(alignment: .center) {
                AvatarImage(avatarUrl: roomInfo?.avatarUrl, imageLoader: imageLoader)
                    .frame(width: 72, height: 72)
                    .clipShape(.circle)

                Text(room.displayName ?? "Unknown room")
                    .font(.title)
                    .textSelection(.enabled)

                if let alias = roomInfo?.canonicalAlias {
                    Text(alias)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            RoomEncryptionBadge(state: room.encryptionState)

            if let topic = room.topic {
                Text(topic.formatAsMarkdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    var usersPlaceholder: some View {
        Group {
            Section("Admins (2)") {
                Text("First admin")
                Text("Second admin")
            }

            Section("Users (4)") {
                Text("First user")
                Text("Second user")
                Text("Third user")
                Text("Fourth user")
            }
        }
        .redacted(reason: .placeholder)
    }

    public var body: some View {
        List {
            header

            userSection(title: "Admins", allMembers: members, withRole: .administrator)
            userSection(title: "Moderators", allMembers: members, withRole: .moderator)
            userSection(title: "Users", allMembers: members, withRole: .user)

            if let roomInfo {
                Section("Extra room info") {
                    Text("Room version: \(roomInfo.roomVersion, default: "Unknown")")
                    Text("Notification count: \(roomInfo.notificationCount)")
                    Text("Highlight count: \(roomInfo.highlightCount)")
                    Text("Marked unread: \(roomInfo.isMarkedUnread.description)")
                    Text("Unread mentions: \(roomInfo.numUnreadMentions)")
                    Text("Unread messages: \(roomInfo.numUnreadMessages)")
                    Text("Unread notifications: \(roomInfo.numUnreadNotifications)")
                }
                .font(.callout)
                .textSelection(.enabled)
            }
        }
        .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
    }
}

#Preview {
    RoomInspectorView<MockRoom, MockRoomMember>(room: MockRoom.previewRoom, members: [], roomInfo: MockRoomInfo(), imageLoader: nil, inspectorVisible: .constant(true))
        .frame(width: 250, height: 500)
}

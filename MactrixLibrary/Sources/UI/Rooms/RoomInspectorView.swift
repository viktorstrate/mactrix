import Models
import SwiftUI

public struct UserProfileRow<Profile: UserProfile>: View {
    let userProfile: Profile
    let imageLoader: ImageLoader?

    @State private var image: Image? = nil

    public init(userProfile: Profile, imageLoader: ImageLoader?) {
        self.userProfile = userProfile
        self.imageLoader = imageLoader
    }

    public var body: some View {
        Label(title: { Text(userProfile.displayName ?? userProfile.userId) }, icon: {
            AvatarImage(avatarUrl: userProfile.avatarUrl, imageLoader: imageLoader, placeholder: { Image(systemName: "person") })
        })
    }
}

struct RoomInspectorMemberRow<RoomMember: Models.RoomMember>: View {
    let member: RoomMember
    let imageLoader: ImageLoader?

    var body: some View {
        UserProfileRow(userProfile: member, imageLoader: imageLoader)
    }
}

public struct RoomInspectorView<Room: Models.Room, RoomMember: Models.RoomMember>: View {
    let room: Room
    let members: [RoomMember]?

    let roomInfo: RoomInfo?
    let imageLoader: ImageLoader?

    @Binding var inspectorVisible: Bool

    public init(room: Room, members: [RoomMember]?, roomInfo: RoomInfo?, imageLoader: ImageLoader?, inspectorVisible: Binding<Bool>) {
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
            VStack(alignment: .center) {
                Text(room.displayName ?? "Unknown Room").font(.title)
                Text(room.topic ?? "No Topic")

                RoomEncryptionBadge(state: room.encryptionState)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)

            if let members = members {
                userSection(title: "Admins", allMembers: members, withRole: .administrator)
                userSection(title: "Moderators", allMembers: members, withRole: .moderator)
                userSection(title: "Users", allMembers: members, withRole: .user)
            } else {
                usersPlaceholder
                    .task(id: room.id) {
                        do {
                            try await room.syncMembers()
                        } catch {
                            print("Failed to sync members in inspector: \(error)")
                        }
                    }
            }

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
        .inspectorColumnWidth(min: 200, ideal: 250, max: 400)
    }
}

#Preview {
    RoomInspectorView<MockRoom, MockRoomMember>(room: MockRoom.previewRoom, members: nil, roomInfo: MockRoomInfo(), imageLoader: nil, inspectorVisible: .constant(true))
        .frame(width: 250, height: 500)
}

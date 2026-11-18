import ContactLinking
import MatrixProtocols
import OSLog
import SwiftUI

struct RoomInspectorMemberRow<RoomMember: MatrixProtocols.RoomMember>: View {
  let member: RoomMember
  let imageLoader: ImageLoader?

  var body: some View {
    // UserProfileRow(profile: member, imageLoader: imageLoader)
    UserProfileRowLarge(profile: member, imageLoader: imageLoader)
  }
}

public struct RoomInspectorView<Room: MatrixProtocols.Room, RoomMember: MatrixProtocols.RoomMember>:
  View
{
  let room: Room
  let members: [RoomMember]

  let roomInfo: RoomInfo?
  let imageLoader: ImageLoader?
  let onSelectUser: (RoomMember) -> Void

  @Binding var inspectorVisible: Bool

  public init(
    room: Room, members: [RoomMember], roomInfo: RoomInfo?, imageLoader: ImageLoader?,
    onSelectUser: @escaping (RoomMember) -> Void, inspectorVisible: Binding<Bool>
  ) {
    self.room = room
    self.members = members
    self.imageLoader = imageLoader
    self.roomInfo = roomInfo
    self.onSelectUser = onSelectUser
    _inspectorVisible = inspectorVisible
  }

  @ViewBuilder
  func userSection(
    title: LocalizedStringResource, allMembers: [RoomMember], withRole role: RoomMemberRole
  ) -> some View {
    let roleMembers = allMembers.filter { $0.roleForPowerLevel == role }
    let sectionTitle = "\(String(localized: title)) (\(roleMembers.count))"
    Section(sectionTitle) {
      ForEach(roleMembers) { member in
        Button(action: { onSelectUser(member) }) {
          RoomInspectorMemberRow(member: member, imageLoader: imageLoader)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  var header: some View {
    VStack(alignment: .center, spacing: 20) {
      VStack(alignment: .center) {
        AvatarImage(
          userID: roomInfo?.directUserId ?? room.id,
          kind: roomInfo?.isDirect == true ? .user : .room,
          displayName: room.displayName,
          avatarUrl: roomInfo?.avatarUrl,
          imageLoader: imageLoader
        )
        .frame(width: 72, height: 72)

        Text(
          ContactDirectory.shared.roomTitle(roomName: room.displayName, roomInfo: roomInfo)
            ?? String(localized: "Unknown room")
        )
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
      Section {
        Text(verbatim: "First admin")
        Text(verbatim: "Second admin")
      } header: {
        Text(verbatim: "Admins (2)")
      }

      Section {
        Text(verbatim: "First user")
        Text(verbatim: "Second user")
        Text(verbatim: "Third user")
        Text(verbatim: "Fourth user")
      } header: {
        Text(verbatim: "Users (4)")
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
          Text("Room version: \(roomInfo.roomVersion, default: String(localized: "Unknown"))")
          Text("Notification count: \(roomInfo.notificationCount)")
          Text("Highlight count: \(roomInfo.highlightCount)")
          Text(
            "Marked unread: \(roomInfo.isMarkedUnread ? String(localized: "Yes") : String(localized: "No"))"
          )
          Text("Unread mentions: \(roomInfo.numUnreadMentions)")
          Text("Unread messages: \(roomInfo.numUnreadMessages)")
          Text("Unread notifications: \(roomInfo.numUnreadNotifications)")
        }
        .font(.callout)
        .textSelection(.enabled)
      }
    }
    .inspectorColumnWidth(min: 200, ideal: 250, max: 900)
  }
}

#Preview {
  RoomInspectorView<MockRoom, MockRoomMember>(
    room: MockRoom.previewRoom, members: [], roomInfo: MockRoomInfo(), imageLoader: nil,
    onSelectUser: { _ in }, inspectorVisible: .constant(true)
  )
  .frame(width: 250, height: 500)
}

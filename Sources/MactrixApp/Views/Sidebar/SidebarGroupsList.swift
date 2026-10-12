import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct SidebarGroupsList: View {
  @Environment(AppState.self) var appState

  var spaces: [SidebarSpaceRoom] {
    appState.matrixClient?.spaceService.spaceRooms ?? []
  }

  var unreadRoomIDs: Set<String> {
    Set(
      (appState.matrixClient?.rooms ?? []).compactMap { room in
        guard !room.room.isSpace(), let info = room.roomInfo else { return nil }
        let isUnread =
          info.isMarkedUnread || info.numUnreadNotifications > 0 || info.numUnreadMentions > 0
        // || info.numUnreadMessages > 0
        return isUnread ? room.id : nil
      })
  }

  var body: some View {
    let unreadIDs = unreadRoomIDs
    let service = appState.matrixClient?.spaceService
    let homeNotifications = unreadIDs.subtracting(service?.roomsWithJoinedSpaceParents ?? []).count
    let spaceNotifications = Dictionary(
      (service?.spaceFilters ?? [])
        .filter { $0.level == 0 }
        .map { filter in
          (filter.spaceRoom.roomId, unreadIDs.intersection(filter.descendants).count)
        }, uniquingKeysWith: { first, _ in first }
    )

    ScrollView {
      VStack(spacing: 8) {
        GroupButton(id: nil, title: "Home", notifications: homeNotifications) {
          Image(systemName: "house.fill")
            .font(.title2)

        }
        ForEach(spaces) { space in
          GroupButton(
            id: space.id, title: space.spaceRoom.displayName,
            notifications: spaceNotifications[space.id, default: 0]
          ) {
            AvatarImage(
              userID: space.id, kind: .room, displayName: space.spaceRoom.displayName,
              avatarUrl: space.spaceRoom.avatarUrl, imageLoader: appState.matrixClient)
          }
          .contextMenu {
            SpaceContextMenu(space: space)
          }
        }
      }
      .frame(width: 62)
    }
  }

}

private struct GroupButton<Content: View>: View {
  @Environment(WindowState.self) var windowState

  let id: String?
  let title: String
  let notifications: Int
  let content: () -> Content

  var body: some View {
    Button {
      if windowState.selectedSpaceId == id {
        // Select the space room to show details about the space itself
        windowState.selectedRoomId = id
      } else {
        windowState.selectedSpaceId = id
      }
    } label: {
      content()
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .background {
          Circle()
            .fill(.background)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 0)
        }
        .overlay {
          Circle()
            .strokeBorder(
              windowState.selectedSpaceId == id ? Color.accentColor : .clear,
              lineWidth: 2
            )
        }
        .overlay {
          if notifications > 0 {

            Text("\(notifications)")
              .foregroundColor(.white)
              .fontWeight(.medium)
              .padding(.vertical, 1)
              .padding(.horizontal, 3)
              .frame(minWidth: 18)
              .background {
                RoundedRectangle(cornerRadius: 10)
                  .fill(.red)
              }
              .compositingGroup()
              .shadow(
                color: Color(red: 0.5, green: 0, blue: 0).opacity(0.35), radius: 3, x: 0, y: 0
              )
              .position(x: 42 - 6, y: 4)
          }
        }
    }
    .focusEffectDisabled()
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(windowState.selectedSpaceId == id ? .isSelected : [])
  }
}

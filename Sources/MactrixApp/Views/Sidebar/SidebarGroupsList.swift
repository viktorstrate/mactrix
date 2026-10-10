import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct SidebarGroupsList: View {
  @Environment(AppState.self) var appState

  var spaces: [SidebarSpaceRoom] {
    appState.matrixClient?.spaceService.spaceRooms ?? []
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        GroupButton(id: nil, title: "Home") {
          Image(systemName: "house.fill")
            .font(.title2)

        }
        ForEach(spaces) { space in
          GroupButton(id: space.id, title: space.spaceRoom.displayName) {
            AvatarImage(
              userID: space.id, kind: .room, displayName: space.spaceRoom.displayName,
              avatarUrl: space.spaceRoom.avatarUrl, imageLoader: appState.matrixClient)
            // RoomRowAvatarImage(
            //   avatarUrl: space.spaceRoom.avatarUrl, placeholderSystemImage: "square.grid.2x2.fill",
            //   imageLoader: appState.matrixClient
            // )
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
    }
    .focusEffectDisabled()
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(windowState.selectedSpaceId == id ? .isSelected : [])
  }
}

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
            .frame(width: 42, height: 42)
            .background(.quaternary, in: Circle())
        }
        ForEach(spaces) { space in
          GroupButton(id: space.id, title: space.spaceRoom.displayName) {
            RoomRowAvatarImage(
              avatarUrl: space.spaceRoom.avatarUrl, placeholderSystemImage: "square.grid.2x2.fill",
              imageLoader: appState.matrixClient
            )
            .frame(width: 42, height: 42)
            .background(.quaternary, in: Circle())
            .clipShape(Circle())
          }
        }
      }
    }
    .frame(width: 62)
  }

}

private struct GroupButton<Content: View>: View {
  @Environment(WindowState.self) var windowState

  let id: String?
  let title: String
  let content: () -> Content

  var body: some View {
    Button {
      windowState.selectedSpaceId = id
    } label: {
      content()
        .overlay {
          Circle().strokeBorder(
            windowState.selectedSpaceId == id ? Color.accentColor : .clear, lineWidth: 3)
        }
    }
    .focusEffectDisabled()
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(windowState.selectedSpaceId == id ? .isSelected : [])
  }
}

import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct SidebarView: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  @State private var members: [MatrixRustSDK.RoomMember] = []
  @State private var membersLoading = false
  @State private var membersError: String?

  var visibleRooms: [SidebarRoom] {
    // filter out rooms whose room info hasn't loaded yet, to avoid flickering
    let joinedRooms = (appState.matrixClient?.rooms ?? []).filter { $0.roomInfo != nil }
    let spaceService = appState.matrixClient?.spaceService

    if let selectedSpaceId = windowState.selectedSpaceId {
      let roomIDs = Set(
        spaceService?.spaceFilters
          .first { $0.spaceRoom.roomId == selectedSpaceId }?.descendants ?? [])
      return joinedRooms.filter { roomIDs.contains($0.id) }
    }

    let roomsWithParents = spaceService?.roomsWithJoinedSpaceParents ?? []
    return joinedRooms.filter { !roomsWithParents.contains($0.id) }
  }

  var selectedSpace: SidebarSpaceRoom? {
    spaces.first { $0.id == windowState.selectedSpaceId }
  }

  var childSpaces: [SidebarSpaceRoom] {
    guard let selectedSpace, case .loaded(let children) = selectedSpace.children else { return [] }
    return children.rooms.filter { $0.spaceRoom.roomType == .space }
  }

  var favorites: [SidebarRoom] {
    visibleRooms.filter { $0.roomInfo?.isFavourite == true }
  }

  var directs: [SidebarRoom] {
    visibleRooms.filter { room in
      let isDirect = room.roomInfo?.isDirect == true
      let favoriteIDs = Set(favorites.map { $0.id })
      return isDirect && !favoriteIDs.contains(room.id)
    }
  }

  var rooms: [SidebarRoom] {
    visibleRooms.filter { room in
      let isSpace = room.room.isSpace()
      let isDirect = room.roomInfo?.isDirect == true
      let favoriteIDs = Set(favorites.map(\.id))
      return !isSpace && !isDirect && !favoriteIDs.contains(room.id)
    }
  }

  var spaces: [SidebarSpaceRoom] {
    appState.matrixClient?.spaceService.spaceRooms ?? []
  }

  var content: some View {
    HStack(spacing: 0) {
      SidebarGroupsList()
      Divider()
      listView
        // force list view to re-render to avoid a rendering bug
        .id(windowState.selectedSpaceId)
    }
    .task(id: selectedSpace?.id) {
      await selectedSpace?.loadChildren()
    }
    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 900)
  }

  var body: some View {
    if #available(macOS 26.0, *) {
      content.safeAreaBar(edge: .bottom) {
        statusContent
          .glassEffect(
            .regular,
            in: ConcentricRectangle(corners: .concentric(minimum: .fixed(12)))
          )
          .padding(8)
      }
    } else {
      content.safeAreaInset(edge: .bottom) {
        statusContent
          .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .padding(8)
      }
    }
  }

  private var statusContent: some View {
    VStack(spacing: 8) {
      SidebarSyncStateView()
      SessionVerificationStatusView()
    }
    .frame(maxWidth: .infinity)
    .padding(12)
  }

  @ViewBuilder
  var listView: some View {
    @Bindable var windowState = windowState

    List(selection: $windowState.selectedRoomId) {
      if !favorites.isEmpty {
        Section("Favorites", isExpanded: $windowState.sidebarSections.favorites) {
          ForEach(favorites) { room in
            MactrixUI.RoomRow(
              title: room.room.displayName() ?? "Unknown room",
              avatarUrl: room.room.avatarUrl(),
              roomInfo: room.roomInfo,
              imageLoader: appState.matrixClient,
              joinRoom: nil
            )
            .contextMenu {
              RoomContextMenu(room: room)
            }
          }
        }
      }

      Section("Directs", isExpanded: $windowState.sidebarSections.directs) {
        ForEach(directs) { room in
          MactrixUI.RoomRow(
            title: room.room.displayName() ?? "Unknown user",
            avatarUrl: room.room.avatarUrl(),
            roomInfo: room.roomInfo,
            imageLoader: appState.matrixClient,
            joinRoom: nil
          )
          .contextMenu {
            RoomContextMenu(room: room)
          }
        }
      }

      Section("Rooms", isExpanded: $windowState.sidebarSections.rooms) {
        ForEach(rooms) { room in
          MactrixUI.RoomRow(
            title: room.room.displayName() ?? "Unknown Room",
            avatarUrl: room.room.avatarUrl(),
            roomInfo: room.roomInfo,
            imageLoader: appState.matrixClient,
            joinRoom: nil
          )
          .contextMenu {
            RoomContextMenu(room: room)
          }
        }
      }

      if !childSpaces.isEmpty {
        Section("Spaces", isExpanded: $windowState.sidebarSections.spaces) {
          ForEach(childSpaces) { space in
            SpaceDisclosureGroup(space: space)
          }
        }
      }
    }
    .navigationSplitViewColumnWidth(min: 230, ideal: 300, max: nil)
    .toolbar {
      AppCommands.createRoomButton(windowState: windowState)
    }
  }
}

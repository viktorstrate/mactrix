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
    let joinedRooms = appState.matrixClient?.rooms ?? []
    let spaceService = appState.matrixClient?.spaceService

    let selectedSpaceRoom = spaceService?.spaceRooms.first {
      $0.id == windowState.selectedSpaceId
    }

    if let selectedSpaceRoom {
      switch selectedSpaceRoom.children {
      case .error:
        return []
      case .loading:
        Task { await selectedSpaceRoom.loadChildren() }
        return []
      case .loaded(let children):
        return joinedRooms.filter { room in
          children.rooms.contains { $0.spaceRoom.id == room.id }
        }
      }
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

  var body: some View {
    HStack(spacing: 0) {
      SidebarGroupsList()
      Divider()
      listView
    }
  }

  @ViewBuilder
  var listView: some View {
    @Bindable var windowState = windowState

    List(selection: $windowState.selectedRoomId) {
      SidebarSyncStateView()

      SessionVerificationStatusView()

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

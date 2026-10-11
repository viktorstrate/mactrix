import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct SpaceContextMenu: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  let space: SidebarSpaceRoom

  var body: some View {

    Button {
      Task {
        do {
          guard let room = try appState.matrixClient?.client.getRoom(roomId: space.spaceRoom.roomId)
          else {
            Logger.viewCycle.error("unable to copy space room link: could not get room")
            return
          }

          let permalink = try await room.matrixToPermalink()
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(permalink, forType: .string)
          Logger.viewCycle.debug("copy room link: \(permalink)")
        } catch {
          Logger.viewCycle.error("unable to copy space room link: \(error)")
        }
      }
    } label: {
      Label("Copy Link", systemImage: "link")
    }

    Button {
      Task {
        do {
          guard let room = try appState.matrixClient?.client.getRoom(roomId: space.spaceRoom.roomId)
          else {
            Logger.viewCycle.error("unable to leave space: could not get room")
            return
          }

          Logger.viewCycle.info("leaving space: \(room.id())")
          try await room.leave()
          try await room.forget()

          if windowState.selectedSpaceId == room.id() {
            windowState.selectedSpaceId = nil
          }

          if windowState.selectedRoomId == room.id() {
            windowState.selectedRoomId = nil
          }
        } catch {
          Logger.viewCycle.error("failed to leave space: \(error)")
        }
      }
    } label: {
      Label("Leave Space", systemImage: "minus.circle")
    }
  }
}

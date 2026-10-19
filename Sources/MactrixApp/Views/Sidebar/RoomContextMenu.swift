import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct RoomContextMenu: View {
  @Environment(WindowState.self) var windowState
  @Environment(\.undoManager) private var undoManager

  let room: SidebarRoom

  var body: some View {
    if let roomInfo = room.roomInfo {
      Button {
        Task {
          do {
            Logger.viewCycle.info("marking room unread/read")
            try await room.room.setUnreadFlag(newValue: !roomInfo.isMarkedUnread)
          } catch {
            Logger.viewCycle.error("failed to mark room unread/read: \(error)")
          }
        }
      } label: {
        if roomInfo.isMarkedUnread {
          Text("Mark as Read")
        } else {
          Text("Mark as Unread")
        }
      }

      Button {
        let previousValue = roomInfo.isFavourite

        Task { @MainActor in
          do {
            Logger.viewCycle.info("mark room favourite: \(!previousValue)")
            try await room.room.setIsFavourite(isFavourite: !previousValue, tagOrder: nil)

            if let undoManager {
              Self.registerFavoriteUndo(
                for: room,
                restoring: previousValue,
                undoManager: undoManager
              )
            }
          } catch {
            Logger.viewCycle.error("failed to mark room favourite: \(error)")
          }
        }

      } label: {
        if roomInfo.isFavourite {
          Label("Unfavorite", systemImage: "heart.slash")
        } else {
          Label("Favorite", systemImage: "heart")
        }
      }

      Button {
        Task {
          do {
            let permalink = try await room.room.matrixToPermalink()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(permalink, forType: .string)
            Logger.viewCycle.debug("copy room link: \(permalink)")
          } catch {
            Logger.viewCycle.error("unable to copy room link: \(error)")
          }
        }
      } label: {
        Label("Copy Link", systemImage: "link")
      }
      .disabled(roomInfo.isDirect)
    }

    Button {
      Task {
        do {
          Logger.viewCycle.info("leaving room: \(room.room.id())")
          try await room.room.leave()
          try await room.room.forget()

          if windowState.selectedRoomId == room.room.id() {
            windowState.selectedRoomId = nil
          }
        } catch {
          Logger.viewCycle.error("failed to leave room: \(error)")
        }
      }
    } label: {
      Label("Leave Room", systemImage: "minus.circle")
    }
  }

  @MainActor
  private static func registerFavoriteUndo(
    for room: SidebarRoom,
    restoring value: Bool,
    undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: room) { [weak undoManager] room in
      guard let undoManager else { return }

      // Register synchronously so UndoManager puts the inverse on the redo stack.
      Self.registerFavoriteUndo(
        for: room,
        restoring: !value,
        undoManager: undoManager
      )

      Task { @MainActor in
        do {
          try await room.room.setIsFavourite(isFavourite: value, tagOrder: nil)
        } catch {
          Logger.viewCycle.error("failed to undo/redo room favourite change: \(error)")
        }
      }
    }

    undoManager.setActionName("Favorite")
  }
}

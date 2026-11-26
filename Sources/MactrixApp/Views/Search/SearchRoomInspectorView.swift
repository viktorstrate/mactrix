import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct SearchRoomInspectorView: View {
  @Environment(WindowState.self) var windowState

  @State var searching: Bool = true
  @State var roomListSelection: String? = nil

  @State var roomSearch: LiveRoomSearch? = nil

  var body: some View {
    List(selection: $roomListSelection) {
      Section("Room search results") {
        if searching {
          Group {
            Text(verbatim: "First room")
            Text(verbatim: "Second room")
            Text(verbatim: "Third room")
          }.redacted(reason: .placeholder)
        } else {
          ForEach(roomSearch?.rooms ?? [], id: \.roomId) { room in
            VStack(alignment: .leading) {
              Text(room.name ?? String(localized: "Unknown name"))
                .help(room.name ?? String(localized: "Unknown name"))
                .lineLimit(1)
                .truncationMode(.tail)
              Text(room.roomId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(room.roomId)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
        }
      }
    }
    .onChange(of: roomListSelection) { _, selectedRoom in
      guard let selectedRoom else { return }
      windowState.selectedRoomId = selectedRoom
    }
    .task(id: windowState.searchQuery) {
      do {
        guard let matrixClient = windowState.matrixClient else { return }

        let roomSearch: LiveRoomSearch
        if let rs = self.roomSearch {
          roomSearch = rs
        } else {
          roomSearch = await LiveRoomSearch(
            roomDirectorySearch: matrixClient.client.roomDirectorySearch())
          self.roomSearch = roomSearch
        }

        guard !windowState.searchQuery.isEmpty else {
          roomSearch.rooms.removeAll()
          return
        }

        searching = true
        defer { searching = false }

        try await Task.sleep(for: .milliseconds(500))

        try await roomSearch.search(query: windowState.searchQuery)
      } catch is CancellationError {
        /* search cancelled */
      } catch {
        Logger.viewCycle.error("room search failed: \(error)")
      }
    }
  }
}

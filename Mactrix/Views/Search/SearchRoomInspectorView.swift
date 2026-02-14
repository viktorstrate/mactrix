import MatrixRustSDK
import OSLog
import SwiftUI
import UI

struct SearchRoomInspectorView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State var searching: Bool = false
    @State var roomListSelection: String? = nil

    @State var roomSearch: LiveRoomSearch? = nil

    var body: some View {
        List(selection: $roomListSelection) {
            Section("Room search results") {
                if searching {
                    Group {
                        Text("First room")
                        Text("Second room")
                        Text("Third room")
                    }.redacted(reason: .placeholder)
                } else {
                    ForEach(roomSearch?.rooms ?? [], id: \.roomId) { room in
                        VStack(alignment: .leading) {
                            Text(room.name ?? "unknown name")
                                .help(room.name ?? "unknown name")
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
                guard let matrixClient = appState.matrixClient else { return }

                let roomSearch: LiveRoomSearch
                if let rs = self.roomSearch {
                    roomSearch = rs
                } else {
                    roomSearch = await LiveRoomSearch(roomDirectorySearch: matrixClient.client.roomDirectorySearch())
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

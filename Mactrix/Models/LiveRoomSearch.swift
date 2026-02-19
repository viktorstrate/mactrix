import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
class LiveRoomSearch {
    let roomDirectorySearch: RoomDirectorySearchProtocol

    @ObservationIgnored fileprivate var resultsHandle: TaskHandle?

    var rooms: [RoomDescription] = []

    init(roomDirectorySearch: RoomDirectorySearchProtocol) async {
        self.roomDirectorySearch = roomDirectorySearch
        await listenToRoomResults()
    }

    deinit {
        Logger.matrixClient.info("LiveRoomSearch deinit")
    }

    private func listenToRoomResults() async {
        Logger.matrixClient.info("room search start listening")

        let listener = AsyncSDKListener<[RoomDirectorySearchEntryUpdate]>()
        resultsHandle = await roomDirectorySearch.results(listener: listener)

        Task { [weak self] in
            let throttledListener = listener
                ._throttle(for: .milliseconds(500), reducing: { result, next in
                    (result ?? []) + next
                })

            for await roomEntriesUpdate in throttledListener {
                guard let self else { break }

                Logger.matrixClient.info("room search updating UI")
                var newRooms = self.rooms
                for update in roomEntriesUpdate {
                    switch update {
                    case let .append(values):
                        newRooms.append(contentsOf: values)
                    case .clear:
                        newRooms.removeAll()
                    case let .pushFront(room):
                        newRooms.insert(room, at: 0)
                    case let .pushBack(room):
                        newRooms.append(room)
                    case .popFront:
                        newRooms.removeFirst()
                    case .popBack:
                        newRooms.removeLast()
                    case let .insert(index, room):
                        newRooms.insert(room, at: Int(index))
                    case let .set(index, room):
                        newRooms[Int(index)] = room
                    case let .remove(index):
                        newRooms.remove(at: Int(index))
                    case let .truncate(length):
                        newRooms.removeSubrange(Int(length) ..< newRooms.count)
                    case let .reset(values: values):
                        newRooms = values
                    }
                }

                // commit all changes at once to prevent UI from flickering
                self.rooms = newRooms
            }
        }
    }

    func search(query: String?) async throws {
        try await roomDirectorySearch.search(filter: query, batchSize: 100, viaServerName: nil)
    }
}

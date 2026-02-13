import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
class LiveRoomSearch {
    let roomDirectorySearch: RoomDirectorySearchProtocol

    @ObservationIgnored fileprivate var resultsListener: MatrixRustListener<[RoomDirectorySearchEntryUpdate]>?

    var rooms: [RoomDescription] = []

    init(roomDirectorySearch: RoomDirectorySearchProtocol) {
        self.roomDirectorySearch = roomDirectorySearch
        startListening()
    }

    deinit {
        Logger.matrixClient.info("LiveRoomSearch deinit")
    }

    private func startListening() {
        Logger.matrixClient.info("room search start listening")

        resultsListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousRoomDirectorySearchEntriesListener { roomEntriesUpdate in
                    Logger.matrixClient.info("room search stream yield")
                    continuation.yield(roomEntriesUpdate)
                }

                return await self.roomDirectorySearch.results(listener: listener)
            },
            onElement: { [weak self] roomEntriesUpdate in
                guard let self else { return }
                
                Logger.matrixClient.info("room search updating UI")
                for update in roomEntriesUpdate {
                    switch update {
                    case let .append(values):
                        self.rooms.append(contentsOf: values)
                    case .clear:
                        self.rooms.removeAll()
                    case let .pushFront(room):
                        self.rooms.insert(room, at: 0)
                    case let .pushBack(room):
                        self.rooms.append(room)
                    case .popFront:
                        self.rooms.removeFirst()
                    case .popBack:
                        self.rooms.removeLast()
                    case let .insert(index, room):
                        self.rooms.insert(room, at: Int(index))
                    case let .set(index, room):
                        self.rooms[Int(index)] = room
                    case let .remove(index):
                        self.rooms.remove(at: Int(index))
                    case let .truncate(length):
                        self.rooms.removeSubrange(Int(length) ..< self.rooms.count)
                    case let .reset(values: values):
                        self.rooms = values
                    }
                }
            }
        )
    }

    func search(query: String?) async throws {
        try await roomDirectorySearch.search(filter: query, batchSize: 100, viaServerName: nil)
    }
}

final class AnonymousRoomDirectorySearchEntriesListener: RoomDirectorySearchEntriesListener {
    let callback: @Sendable ([MatrixRustSDK.RoomDirectorySearchEntryUpdate]) -> Void
    init(callback: @Sendable @escaping ([MatrixRustSDK.RoomDirectorySearchEntryUpdate]) -> Void) { self.callback = callback }

    func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomDirectorySearchEntryUpdate]) {
        callback(roomEntriesUpdate)
    }
}

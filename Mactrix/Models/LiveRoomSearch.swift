import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
class LiveRoomSearch {
    let roomDirectorySearch: RoomDirectorySearchProtocol

    @ObservationIgnored fileprivate var resultsTaskHandle: TaskHandle?
    @ObservationIgnored fileprivate var searchResultsTask: Task<Void, Never>?

    var rooms: [RoomDescription] = []

    init(roomDirectorySearch: RoomDirectorySearchProtocol) {
        self.roomDirectorySearch = roomDirectorySearch
        startListening()
    }

    deinit {
        Logger.matrixClient.info("LiveRoomSearch deinit")
        searchResultsTask?.cancel()
        searchResultsTask = nil
    }

    private func startListening() {
        Logger.matrixClient.info("room search start listening")

        let stream = AsyncStream { continuation in
            let listener = AnonymousRoomDirectorySearchEntriesListener { roomEntriesUpdate in
                Logger.matrixClient.info("room search stream yield")
                continuation.yield(roomEntriesUpdate)
            }

            Task {
                resultsTaskHandle = await roomDirectorySearch.results(listener: listener)
            }

            continuation.onTermination = { _ in
                Logger.matrixClient.info("room search continuation terminated")
            }
        }

        searchResultsTask = Task { [weak self] in
            for await roomEntriesUpdate in stream {
                guard let self else { break }

                Logger.matrixClient.info("room search updating UI")
                for update in roomEntriesUpdate {
                    switch update {
                    case let .append(values):
                        rooms.append(contentsOf: values)
                    case .clear:
                        rooms.removeAll()
                    case let .pushFront(room):
                        rooms.insert(room, at: 0)
                    case let .pushBack(room):
                        rooms.append(room)
                    case .popFront:
                        rooms.removeFirst()
                    case .popBack:
                        rooms.removeLast()
                    case let .insert(index, room):
                        rooms.insert(room, at: Int(index))
                    case let .set(index, room):
                        rooms[Int(index)] = room
                    case let .remove(index):
                        rooms.remove(at: Int(index))
                    case let .truncate(length):
                        rooms.removeSubrange(Int(length) ..< rooms.count)
                    case let .reset(values: values):
                        rooms = values
                    }
                }
            }

            Logger.matrixClient.info("room search background task ended")
        }
    }

    func search(query: String?) async throws {
        try await roomDirectorySearch.search(filter: query, batchSize: 100, viaServerName: nil)
    }
}

final class AnonymousRoomDirectorySearchEntriesListener: RoomDirectorySearchEntriesListener {
    let callback: @Sendable ([MatrixRustSDK.RoomDirectorySearchEntryUpdate]) -> Void
    init(callback: @Sendable @escaping ([MatrixRustSDK.RoomDirectorySearchEntryUpdate]) -> Void) { self.callback = callback }

    nonisolated func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomDirectorySearchEntryUpdate]) {
        callback(roomEntriesUpdate)
    }
}

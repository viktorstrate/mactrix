import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public class LiveRoomSearch {
  public let roomDirectorySearch: RoomDirectorySearchProtocol

  @ObservationIgnored fileprivate var resultsHandle: TaskHandle?

  public var rooms: [RoomDescription] = []

  public init(roomDirectorySearch: RoomDirectorySearchProtocol) async {
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
      for await roomEntriesUpdate in listener {
        guard let self else { break }

        Logger.matrixClient.info("room search updating UI")
        for update in roomEntriesUpdate {
          switch update {
          case .append(let values):
            self.rooms.append(contentsOf: values)
          case .clear:
            self.rooms.removeAll()
          case .pushFront(let room):
            self.rooms.insert(room, at: 0)
          case .pushBack(let room):
            self.rooms.append(room)
          case .popFront:
            self.rooms.removeFirst()
          case .popBack:
            self.rooms.removeLast()
          case .insert(let index, let room):
            self.rooms.insert(room, at: Int(index))
          case .set(let index, let room):
            self.rooms[Int(index)] = room
          case .remove(let index):
            self.rooms.remove(at: Int(index))
          case .truncate(let length):
            self.rooms.removeSubrange(Int(length)..<self.rooms.count)
          case .reset(let values):
            self.rooms = values
          }
        }
      }
    }
  }

  public func search(query: String?) async throws {
    try await roomDirectorySearch.search(filter: query, batchSize: 100, viaServerName: nil)
  }
}

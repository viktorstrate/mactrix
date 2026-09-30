import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class LiveSpaceRoomList {
  public let spaceService: LiveSpaceService
  public let spaceRoomList: SpaceRoomList

  public var space: SpaceRoom?
  public var rooms: [SidebarSpaceRoom] = []
  public var paginationState: SpaceRoomListPaginationState = .loading

  @ObservationIgnored fileprivate var spaceHandle: TaskHandle?
  @ObservationIgnored fileprivate var roomsHandle: TaskHandle?
  @ObservationIgnored fileprivate var paginateHandle: TaskHandle?

  public init(spaceService: LiveSpaceService, spaceRoomList: SpaceRoomList) {
    self.spaceService = spaceService
    self.spaceRoomList = spaceRoomList

    listenToSpaceRoom()
    listenToPagination()

    Task {
      await listenToRooms()
      await loadChildRooms()
    }
  }

  deinit {
    Logger.liveSpaceRoomList.debug("LiveSpaceRoomList deinit")
  }

  private func listenToSpaceRoom() {
    let spaceListener = AsyncSDKListener<SpaceRoom?>()
    spaceHandle = spaceRoomList.subscribeToSpaceUpdates(listener: spaceListener)

    Task { [weak self] in
      for await space in spaceListener.debounce(for: .milliseconds(500)) {
        guard let self else { break }
        self.space = space
      }
    }
  }

  private func listenToRooms() async {
    let roomsListener = AsyncSDKListener<[SpaceListUpdate]>()
    roomsHandle = await spaceRoomList.subscribeToRoomUpdate(listener: roomsListener)

    Task { [weak self] in
      for await roomUpdates in roomsListener {
        guard let self else { return }

        for update in roomUpdates {
          switch update {
          case .append(let values):
            self.rooms.append(
              contentsOf: values.map {
                SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0)
              })
          case .clear:
            self.rooms.removeAll()
          case .pushFront(let room):
            self.rooms.insert(
              SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: 0)
          case .pushBack(let room):
            self.rooms.append(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room))
          case .popFront:
            self.rooms.removeFirst()
          case .popBack:
            self.rooms.removeLast()
          case .insert(let index, let room):
            self.rooms.insert(
              SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: Int(index))
          case .set(let index, let room):
            self.rooms[Int(index)] = SidebarSpaceRoom(
              spaceService: self.spaceService, spaceRoom: room)
          case .remove(let index):
            self.rooms.remove(at: Int(index))
          case .truncate(let length):
            self.rooms.removeSubrange(Int(length)..<self.rooms.count)
          case .reset(let values):
            self.rooms = values.map {
              SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0)
            }
          }
        }
      }
    }
  }

  private func listenToPagination() {
    let paginateListener = AsyncSDKListener<SpaceRoomListPaginationState>()
    paginateHandle = spaceRoomList.subscribeToPaginationStateUpdates(listener: paginateListener)

    Task { [weak self] in
      for await state in paginateListener.debounce(for: .milliseconds(500)) {
        self?.paginationState = state
      }
    }
  }

  public func loadChildRooms() async {
    do {
      try await spaceRoomList.paginate()
    } catch {
      Logger.liveSpaceRoomList.error("Failed to paginate space list: \(error)")
    }
  }
}

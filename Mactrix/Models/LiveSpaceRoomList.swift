import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
final class LiveSpaceRoomList {
    let spaceService: LiveSpaceService
    let spaceRoomList: SpaceRoomList

    var space: SpaceRoom?
    var rooms: [SidebarSpaceRoom] = []
    var paginationState: SpaceRoomListPaginationState = .loading

    @ObservationIgnored fileprivate var spaceHandle: TaskHandle?
    @ObservationIgnored fileprivate var roomsHandle: TaskHandle?
    @ObservationIgnored fileprivate var paginateHandle: TaskHandle?

    init(spaceService: LiveSpaceService, spaceRoomList: SpaceRoomList) {
        self.spaceService = spaceService
        self.spaceRoomList = spaceRoomList

        listenToSpaceRoom()
        listenToRooms()
        listenToPagination()

        Task {
            await loadChildRooms()
        }
    }

    deinit {
        Logger.liveSpaceRoomList.debug("LiveSpaceRoomList deinit")
    }

    fileprivate func listenToSpaceRoom() {
        let spaceListener = AsyncSDKListener<SpaceRoom?>()
        spaceHandle = spaceRoomList.subscribeToSpaceUpdates(listener: spaceListener)

        Task { [weak self] in
            for await space in spaceListener._throttle(for: .milliseconds(500)) {
                guard let self else { break }
                self.space = space
            }
        }
    }

    fileprivate func listenToRooms() {
        let roomsListener = AsyncSDKListener<[SpaceListUpdate]>()
        roomsHandle = spaceRoomList.subscribeToRoomUpdate(listener: roomsListener)

        Task { [weak self] in
            let throttledListener = roomsListener
                ._throttle(for: .milliseconds(500), reducing: { result, next in
                    (result ?? []) + next
                })

            for await roomUpdates in throttledListener {
                guard let self else { return }

                var newRooms = self.rooms
                for update in roomUpdates {
                    switch update {
                    case let .append(values):
                        newRooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0) })
                    case .clear:
                        newRooms.removeAll()
                    case let .pushFront(room):
                        newRooms.insert(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: 0)
                    case let .pushBack(room):
                        newRooms.append(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room))
                    case .popFront:
                        newRooms.removeFirst()
                    case .popBack:
                        newRooms.removeLast()
                    case let .insert(index, room):
                        newRooms.insert(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: Int(index))
                    case let .set(index, room):
                        newRooms[Int(index)] = SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room)
                    case let .remove(index):
                        newRooms.remove(at: Int(index))
                    case let .truncate(length):
                        newRooms.removeSubrange(Int(length) ..< newRooms.count)
                    case let .reset(values: values):
                        newRooms = values.map { SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0) }
                    }
                }

                // commit all changes at once to prevent UI from flickering
                self.rooms = newRooms
            }
        }
    }

    fileprivate func listenToPagination() {
        let paginateListener = AsyncSDKListener<SpaceRoomListPaginationState>()
        paginateHandle = spaceRoomList.subscribeToPaginationStateUpdates(listener: paginateListener)

        Task { [weak self] in
            for await state in paginateListener._throttle(for: .milliseconds(500)) {
                self?.paginationState = state
            }
        }
    }

    func loadChildRooms() async {
        do {
            try await spaceRoomList.paginate()
        } catch {
            Logger.viewCycle.error("Failed to paginate space list: \(error)")
        }
    }
}

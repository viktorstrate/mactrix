import Foundation
import MatrixRustSDK

@Observable
final class LiveSpaceRoomList {
    let spaceService: LiveSpaceService
    let spaceRoomList: SpaceRoomList

    var space: SpaceRoom?
    var rooms: [SidebarSpaceRoom] = []
    var paginationState: SpaceRoomListPaginationState = .loading

    fileprivate var spaceListenerHandle: TaskHandle?
    fileprivate var roomsListenerHandle: TaskHandle?
    fileprivate var paginateListenerHandle: TaskHandle?

    init(spaceService: LiveSpaceService, spaceRoomList: SpaceRoomList) {
        self.spaceService = spaceService
        self.spaceRoomList = spaceRoomList
        startListening()
        loadChildRooms()
    }

    fileprivate func startListening() {
        spaceListenerHandle = spaceRoomList.subscribeToSpaceUpdates(listener: self)
        roomsListenerHandle = spaceRoomList.subscribeToRoomUpdate(listener: self)
        paginateListenerHandle = spaceRoomList.subscribeToPaginationStateUpdates(listener: self)
    }

    func loadChildRooms() {
        Task {
            do {
                try await spaceRoomList.paginate()
            } catch {
                print("Failed to paginate space list: \(error)")
            }
        }
    }
}

extension LiveSpaceRoomList: SpaceRoomListSpaceListener, SpaceRoomListEntriesListener, SpaceRoomListPaginationStateListener {
    func onUpdate(paginationState: MatrixRustSDK.SpaceRoomListPaginationState) {
        self.paginationState = paginationState
    }

    func onUpdate(space: MatrixRustSDK.SpaceRoom?) {
        self.space = space
    }

    func onUpdate(rooms roomUpdates: [MatrixRustSDK.SpaceListUpdate]) {
        for update in roomUpdates {
            switch update {
            case let .append(values):
                rooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: spaceService, spaceRoom: $0) })
            case .clear:
                rooms.removeAll()
            case let .pushFront(room):
                rooms.insert(SidebarSpaceRoom(spaceService: spaceService, spaceRoom: room), at: 0)
            case let .pushBack(room):
                rooms.append(SidebarSpaceRoom(spaceService: spaceService, spaceRoom: room))
            case .popFront:
                rooms.removeFirst()
            case .popBack:
                rooms.removeLast()
            case let .insert(index, room):
                rooms.insert(SidebarSpaceRoom(spaceService: spaceService, spaceRoom: room), at: Int(index))
            case let .set(index, room):
                rooms[Int(index)] = SidebarSpaceRoom(spaceService: spaceService, spaceRoom: room)
            case let .remove(index):
                rooms.remove(at: Int(index))
            case let .truncate(length):
                rooms.removeSubrange(Int(length) ..< rooms.count)
            case let .reset(values: values):
                rooms = values.map { SidebarSpaceRoom(spaceService: spaceService, spaceRoom: $0) }
            }
        }
    }
}

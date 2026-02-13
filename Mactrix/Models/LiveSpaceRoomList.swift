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

    @ObservationIgnored fileprivate var spaceListener: MatrixRustListener<SpaceRoom?>?
    @ObservationIgnored fileprivate var roomsListener: MatrixRustListener<[SpaceListUpdate]>?
    @ObservationIgnored fileprivate var paginateListener: MatrixRustListener<SpaceRoomListPaginationState>?

    init(spaceService: LiveSpaceService, spaceRoomList: SpaceRoomList) {
        self.spaceService = spaceService
        self.spaceRoomList = spaceRoomList
        startListening()
        loadChildRooms()
    }

    deinit {
        Logger.liveSpaceRoomList.debug("LiveSpaceRoomList deinit")
    }

    fileprivate func startListening() {
        spaceListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousSpaceRoomListSpaceListener { space in
                    continuation.yield(space)
                }
                return self.spaceRoomList.subscribeToSpaceUpdates(listener: listener)
            },
            onElement: { [weak self] space in
                self?.space = space
            }
        )

        roomsListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousSpaceRoomListEntriesListener { rooms in
                    continuation.yield(rooms)
                }
                return self.spaceRoomList.subscribeToRoomUpdate(listener: listener)
            },
            onElement: { [weak self] roomUpdates in
                guard let self else { return }

                for update in roomUpdates {
                    switch update {
                    case let .append(values):
                        rooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0) })
                    case .clear:
                        rooms.removeAll()
                    case let .pushFront(room):
                        rooms.insert(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: 0)
                    case let .pushBack(room):
                        rooms.append(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room))
                    case .popFront:
                        rooms.removeFirst()
                    case .popBack:
                        rooms.removeLast()
                    case let .insert(index, room):
                        rooms.insert(SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room), at: Int(index))
                    case let .set(index, room):
                        rooms[Int(index)] = SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: room)
                    case let .remove(index):
                        rooms.remove(at: Int(index))
                    case let .truncate(length):
                        rooms.removeSubrange(Int(length) ..< rooms.count)
                    case let .reset(values: values):
                        rooms = values.map { SidebarSpaceRoom(spaceService: self.spaceService, spaceRoom: $0) }
                    }
                }
            }
        )
        
        paginateListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousSpaceRoomListPaginationStateListener { paginationState in
                    continuation.yield(paginationState)
                }
                return self.spaceRoomList.subscribeToPaginationStateUpdates(listener: listener)
            },
            onElement: { [weak self] state in
                self?.paginationState = state
            }
        )
    }

    func loadChildRooms() {
        Task {
            do {
                try await spaceRoomList.paginate()
            } catch {
                Logger.viewCycle.error("Failed to paginate space list: \(error)")
            }
        }
    }
}

final class AnonymousSpaceRoomListPaginationStateListener: SpaceRoomListPaginationStateListener {
    let callback: @Sendable (MatrixRustSDK.SpaceRoomListPaginationState) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.SpaceRoomListPaginationState) -> Void) { self.callback = callback }

    func onUpdate(paginationState: MatrixRustSDK.SpaceRoomListPaginationState) {
        callback(paginationState)
    }
}

final class AnonymousSpaceRoomListEntriesListener: SpaceRoomListEntriesListener {
    let callback: @Sendable ([MatrixRustSDK.SpaceListUpdate]) -> Void
    init(callback: @Sendable @escaping ([MatrixRustSDK.SpaceListUpdate]) -> Void) { self.callback = callback }

    func onUpdate(rooms: [MatrixRustSDK.SpaceListUpdate]) {
        callback(rooms)
    }
}

final class AnonymousSpaceRoomListSpaceListener: SpaceRoomListSpaceListener {
    let callback: @Sendable (MatrixRustSDK.SpaceRoom?) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.SpaceRoom?) -> Void) { self.callback = callback }

    func onUpdate(space: MatrixRustSDK.SpaceRoom?) {
        callback(space)
    }
}

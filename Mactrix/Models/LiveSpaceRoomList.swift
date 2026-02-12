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

    @ObservationIgnored fileprivate var spaceListenerHandle: TaskHandle?
    @ObservationIgnored fileprivate var roomsListenerHandle: TaskHandle?
    @ObservationIgnored fileprivate var paginateListenerHandle: TaskHandle?

    @ObservationIgnored fileprivate var spaceListenerTask: Task<Void, Never>?
    @ObservationIgnored fileprivate var roomsListenerTask: Task<Void, Never>?
    @ObservationIgnored fileprivate var paginateListenerTask: Task<Void, Never>?

    init(spaceService: LiveSpaceService, spaceRoomList: SpaceRoomList) {
        self.spaceService = spaceService
        self.spaceRoomList = spaceRoomList
        startListening()
        loadChildRooms()
    }

    deinit {
        Logger.liveSpaceRoomList.debug("LiveSpaceRoomList deinit")
        spaceListenerTask?.cancel()
        spaceListenerTask = nil
        roomsListenerTask?.cancel()
        roomsListenerTask = nil
        paginateListenerTask?.cancel()
        paginateListenerTask = nil
    }

    fileprivate func startListening() {
        let spaceStream = AsyncStream { continuation in
            let listener = AnonymousSpaceRoomListSpaceListener { space in
                continuation.yield(space)
            }
            spaceListenerHandle = spaceRoomList.subscribeToSpaceUpdates(listener: listener)
        }

        let roomsStream = AsyncStream { continuation in
            let listener = AnonymousSpaceRoomListEntriesListener { rooms in
                continuation.yield(rooms)
            }
            roomsListenerHandle = spaceRoomList.subscribeToRoomUpdate(listener: listener)
        }

        let paginateStream = AsyncStream { continuation in
            let listener = AnonymousSpaceRoomListPaginationStateListener { paginationState in
                continuation.yield(paginationState)
            }
            paginateListenerHandle = spaceRoomList.subscribeToPaginationStateUpdates(listener: listener)
        }

        spaceListenerTask = Task { [weak self] in
            for await space in spaceStream {
                guard let self else { break }
                self.space = space
            }
        }

        roomsListenerTask = Task { [weak self] in
            for await roomUpdates in roomsStream {
                guard let self else { break }

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
        }

        paginateListenerTask = Task { [weak self] in
            for await state in paginateStream {
                guard let self else { break }
                self.paginationState = state
            }
        }
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

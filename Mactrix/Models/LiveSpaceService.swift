import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class LiveSpaceService {
    public let spaceService: SpaceService

    public var spaceRooms: [SidebarSpaceRoom] = []

    @ObservationIgnored private var spaceListener: MatrixRustListener<[SpaceListUpdate]>?

    public init(spaceService: SpaceService) {
        self.spaceService = spaceService

        Task {
            await startListener()

            let joinedSpaces = await spaceService.topLevelJoinedSpaces()
            Logger.liveSpaceService.debug("Joined spaces: \(joinedSpaces)")
        }
    }

    private func startListener() async {
        spaceListener = await MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousSpaceServiceJoinedSpacesListener { roomUpdates in
                    continuation.yield(roomUpdates)
                }
                return await self.spaceService.subscribeToTopLevelJoinedSpaces(listener: listener)
            },
            onElement: { [weak self] roomUpdates in
                guard let self else { return }

                for update in roomUpdates {
                    switch update {
                    case let .append(values):
                        spaceRooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) })
                    case .clear:
                        spaceRooms.removeAll()
                    case let .pushFront(room):
                        spaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: 0)
                    case let .pushBack(room):
                        spaceRooms.append(SidebarSpaceRoom(spaceService: self, spaceRoom: room))
                    case .popFront:
                        spaceRooms.removeFirst()
                    case .popBack:
                        spaceRooms.removeLast()
                    case let .insert(index, room):
                        spaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: Int(index))
                    case let .set(index, room):
                        spaceRooms[Int(index)] = SidebarSpaceRoom(spaceService: self, spaceRoom: room)
                    case let .remove(index):
                        spaceRooms.remove(at: Int(index))
                    case let .truncate(length):
                        spaceRooms.removeSubrange(Int(length) ..< spaceRooms.count)
                    case let .reset(values: values):
                        spaceRooms = values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) }
                    }
                }
            }
        )
    }
}

final class AnonymousSpaceServiceJoinedSpacesListener: SpaceServiceJoinedSpacesListener {
    let callback: @Sendable ([MatrixRustSDK.SpaceListUpdate]) -> Void
    init(callback: @Sendable @escaping ([MatrixRustSDK.SpaceListUpdate]) -> Void) { self.callback = callback }

    func onUpdate(roomUpdates: [MatrixRustSDK.SpaceListUpdate]) {
        callback(roomUpdates)
    }
}

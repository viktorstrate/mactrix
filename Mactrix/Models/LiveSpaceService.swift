import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class LiveSpaceService {
    public let spaceService: SpaceService

    public var spaceRooms: [SidebarSpaceRoom] = []

    @ObservationIgnored private var spaceHandle: TaskHandle?

    public init(spaceService: SpaceService) {
        self.spaceService = spaceService

        Task {
            await self.listenToJoinedSpaces()

            let joinedSpaces = await spaceService.topLevelJoinedSpaces()
            Logger.liveSpaceService.debug("Joined spaces: \(joinedSpaces)")
        }
    }

    private func listenToJoinedSpaces() async {
        let listener = AsyncSDKListener<[SpaceListUpdate]>()
        self.spaceHandle = await self.spaceService.subscribeToTopLevelJoinedSpaces(listener: listener)

        Task { [weak self] in
            let throttledListener = listener
                ._throttle(for: .milliseconds(500), reducing: { result, next in
                    (result ?? []) + next
                })

            for await roomUpdates in throttledListener {
                guard let self else { break }

                var newSpaceRooms = self.spaceRooms
                for update in roomUpdates {
                    switch update {
                    case let .append(values):
                        newSpaceRooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) })
                    case .clear:
                        newSpaceRooms.removeAll()
                    case let .pushFront(room):
                        newSpaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: 0)
                    case let .pushBack(room):
                        newSpaceRooms.append(SidebarSpaceRoom(spaceService: self, spaceRoom: room))
                    case .popFront:
                        newSpaceRooms.removeFirst()
                    case .popBack:
                        newSpaceRooms.removeLast()
                    case let .insert(index, room):
                        newSpaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: Int(index))
                    case let .set(index, room):
                        newSpaceRooms[Int(index)] = SidebarSpaceRoom(spaceService: self, spaceRoom: room)
                    case let .remove(index):
                        newSpaceRooms.remove(at: Int(index))
                    case let .truncate(length):
                        newSpaceRooms.removeSubrange(Int(length) ..< newSpaceRooms.count)
                    case let .reset(values: values):
                        newSpaceRooms = values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) }
                    }
                }

                self.spaceRooms = newSpaceRooms
            }
        }
    }
}

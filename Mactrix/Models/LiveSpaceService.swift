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
            for await roomUpdates in listener {
                guard let self else { break }

                for update in roomUpdates {
                    switch update {
                    case let .append(values):
                        self.spaceRooms.append(contentsOf: values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) })
                    case .clear:
                        self.spaceRooms.removeAll()
                    case let .pushFront(room):
                        self.spaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: 0)
                    case let .pushBack(room):
                        self.spaceRooms.append(SidebarSpaceRoom(spaceService: self, spaceRoom: room))
                    case .popFront:
                        self.spaceRooms.removeFirst()
                    case .popBack:
                        self.spaceRooms.removeLast()
                    case let .insert(index, room):
                        self.spaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: Int(index))
                    case let .set(index, room):
                        self.spaceRooms[Int(index)] = SidebarSpaceRoom(spaceService: self, spaceRoom: room)
                    case let .remove(index):
                        self.spaceRooms.remove(at: Int(index))
                    case let .truncate(length):
                        self.spaceRooms.removeSubrange(Int(length) ..< self.spaceRooms.count)
                    case let .reset(values: values):
                        self.spaceRooms = values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) }
                    }
                }
            }
        }
    }
}

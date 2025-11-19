import Foundation
import MatrixRustSDK

@Observable public final class LiveSpaceService {
    public let spaceService: SpaceService

    public var spaceRooms: [SidebarSpaceRoom] = []

    var listenerTaskHandle: TaskHandle?

    public init(spaceService: SpaceService) {
        self.spaceService = spaceService

        Task {
            listenerTaskHandle = await spaceService.subscribeToJoinedSpaces(listener: self)

            let joinedSpaces = await spaceService.joinedSpaces()
            print("Joined spaces: \(joinedSpaces)")
        }
    }
}

extension LiveSpaceService: SpaceServiceJoinedSpacesListener {
    public func onUpdate(roomUpdates: [MatrixRustSDK.SpaceListUpdate]) {
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
}

import Foundation
import MatrixRustSDK

@MainActor @Observable
public final class SidebarSpaceRoom {
    let spaceRoom: SpaceRoom

    var children: Children = .loading

    private let spaceService: LiveSpaceService

    init(spaceService: LiveSpaceService, spaceRoom: SpaceRoom) {
        self.spaceService = spaceService
        self.spaceRoom = spaceRoom
    }

    func loadChildren() async {
        if case .loaded(children: _) = children {
            return
        }

        do {
            let result = try await spaceService.spaceService.spaceRoomList(spaceId: spaceRoom.roomId)
            children = .loaded(children: LiveSpaceRoomList(spaceService: spaceService, spaceRoomList: result))
        } catch {
            children = .error(error: error)
        }
    }

    enum Children {
        case loading
        case loaded(children: LiveSpaceRoomList)
        case error(error: Error)
    }
}

extension SidebarSpaceRoom: Identifiable {
    public nonisolated var id: String { spaceRoom.roomId }
}

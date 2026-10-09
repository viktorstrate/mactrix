import Foundation
import MatrixRustSDK

@MainActor @Observable
public final class SidebarSpaceRoom {
  public let spaceRoom: SpaceRoom

  public private(set) var children: Children = .loading
  private var loadingChildren = false

  private let spaceService: LiveSpaceService

  public init(spaceService: LiveSpaceService, spaceRoom: SpaceRoom) {
    self.spaceService = spaceService
    self.spaceRoom = spaceRoom
  }

  public func loadChildren() async {
    if case .loaded = children {
      return
    }
    
    guard !loadingChildren else { return }
    loadingChildren = true
    defer { loadingChildren = false }

    do {
      let result = try await spaceService.spaceService.spaceRoomList(spaceId: spaceRoom.roomId)
      children = .loaded(
        children: LiveSpaceRoomList(spaceService: spaceService, spaceRoomList: result))
    } catch {
      children = .error(error: error)
    }
  }

  public enum Children {
    case loading
    case loaded(children: LiveSpaceRoomList)
    case error(error: Error)
  }
}

extension SidebarSpaceRoom: Identifiable {
  public nonisolated var id: String {
    spaceRoom.roomId
  }
}

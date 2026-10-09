import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class LiveSpaceService {
  weak private let client: MatrixRustSDK.ClientProtocol?
  public let spaceService: SpaceService

  public var spaceRooms: [SidebarSpaceRoom] = []

  public private(set) var roomsWithJoinedSpaceParents: Set<String> = []

  @ObservationIgnored private var spaceHandle: TaskHandle?
  @ObservationIgnored private var filtersHandle: TaskHandle?
  @ObservationIgnored private var setupTask: Task<Void, Never>?
  @ObservationIgnored private var spacesTask: Task<Void, Never>?
  @ObservationIgnored private var filtersTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var parentsNeedsRefresh = false
  @ObservationIgnored private var spaceGraphLoaded = false

  public init(client: MatrixRustSDK.ClientProtocol, spaceService: SpaceService) {
    self.client = client
    self.spaceService = spaceService

    setupTask = Task { [weak self] in
      await self?.listenToJoinedSpaces()
      await self?.listenToSpaceFilters()

      // initializes the spaces graph
      _ = await spaceService.topLevelJoinedSpaces()
      guard !Task.isCancelled, let self else { return }
      self.spaceGraphLoaded = true
      self.refreshRoomsWithParents()
    }
  }

  deinit {
    setupTask?.cancel()
    spacesTask?.cancel()
    filtersTask?.cancel()
    refreshTask?.cancel()
    spaceHandle?.cancel()
    filtersHandle?.cancel()
  }

  private func listenToSpaceFilters() async {
    let listener = AsyncSDKListener<[SpaceFilterUpdate]>()
    filtersHandle = await spaceService.subscribeToSpaceFilters(listener: listener)
    filtersTask = Task { [weak self] in
      for await _ in listener {
        guard let self else { break }
        self.refreshRoomsWithParents()
      }
    }
  }

  private func refreshRoomsWithParents() {
    parentsNeedsRefresh = true
    guard spaceGraphLoaded, refreshTask == nil else { return }

    let service = spaceService
    refreshTask = Task { [weak self] in
      while self?.parentsNeedsRefresh == true && !Task.isCancelled {
        guard let rooms = self?.client?.rooms() else { return }
        self?.parentsNeedsRefresh = false
        var children: Set<String> = []
        for room in rooms {
          guard !Task.isCancelled else { return }
          do {
            let parents = try await service.joinedParentIdsOfChild(childId: room.id())
            if !parents.isEmpty {
              children.insert(room.id())
            }
          } catch {
            Logger.liveSpaceService.error("Failed to look up joined space parents: \(error)")
          }
        }
        if let self {
          self.roomsWithJoinedSpaceParents = children
          self.refreshTask = nil
        }
      }
    }
  }

  private func listenToJoinedSpaces() async {
    let listener = AsyncSDKListener<[SpaceListUpdate]>()
    self.spaceHandle = await self.spaceService.subscribeToTopLevelJoinedSpaces(listener: listener)

    spacesTask = Task { [weak self] in
      for await roomUpdates in listener {
        guard let self else { break }

        for update in roomUpdates {
          switch update {
          case .append(let values):
            self.spaceRooms.append(
              contentsOf: values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) })
          case .clear:
            self.spaceRooms.removeAll()
          case .pushFront(let room):
            self.spaceRooms.insert(SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: 0)
          case .pushBack(let room):
            self.spaceRooms.append(SidebarSpaceRoom(spaceService: self, spaceRoom: room))
          case .popFront:
            self.spaceRooms.removeFirst()
          case .popBack:
            self.spaceRooms.removeLast()
          case .insert(let index, let room):
            self.spaceRooms.insert(
              SidebarSpaceRoom(spaceService: self, spaceRoom: room), at: Int(index))
          case .set(let index, let room):
            self.spaceRooms[Int(index)] = SidebarSpaceRoom(spaceService: self, spaceRoom: room)
          case .remove(let index):
            self.spaceRooms.remove(at: Int(index))
          case .truncate(let length):
            self.spaceRooms.removeSubrange(Int(length)..<self.spaceRooms.count)
          case .reset(let values):
            self.spaceRooms = values.map { SidebarSpaceRoom(spaceService: self, spaceRoom: $0) }
          }
        }
      }
    }
  }
}

import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let id: String
    public private(set) var room: MatrixRustSDK.Room
    public var roomInfo: RoomInfo?

    @ObservationIgnored private var roomInfoHandle: TaskHandle?
    @ObservationIgnored private var listenerTask: Task<Void, Never>?

    public init(room: MatrixRustSDK.Room) {
        self.id = room.id()
        self.room = room

        Task {
            do {
                roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch initial room info: \(error)")
            }

            listenToRoomInfo()
        }
    }

    /// Updates the underlying room reference without replacing this instance.
    /// Preserves object identity and loaded roomInfo while ensuring the room
    /// object stays current. Re-subscribes to room info updates on the new reference.
    public func updateRoom(_ newRoom: MatrixRustSDK.Room) {
        assert(id == newRoom.id())
        room = newRoom
        listenerTask?.cancel()
        roomInfoHandle = nil
        Task {
            do {
                roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch room info on update: \(error)")
            }
            listenToRoomInfo()
        }
    }

    private func listenToRoomInfo() {
        let listener = AsyncSDKListener<RoomInfo>()
        roomInfoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        listenerTask = Task { [weak self] in
            for await roomInfo in listener._throttle(for: .milliseconds(500)) {
                guard let self, !Task.isCancelled else { break }
                self.roomInfo = roomInfo
            }
        }
    }
}

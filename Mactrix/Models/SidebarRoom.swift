import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let room: MatrixRustSDK.Room
    public var roomInfo: RoomInfo?

    @ObservationIgnored private var roomInfoHandle: TaskHandle?

    public nonisolated var id: String {
        room.id()
    }

    public init(room: MatrixRustSDK.Room) {
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

    private func listenToRoomInfo() {
        let listener = AsyncSDKListener<RoomInfo>()
        roomInfoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        Task { [weak self] in
            for await roomInfo in listener {
                guard let self else { break }
                self.roomInfo = roomInfo
            }
        }
    }
}

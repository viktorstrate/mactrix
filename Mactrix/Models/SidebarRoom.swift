import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let room: MatrixRustSDK.Room
    public var roomInfo: RoomInfo?

    public nonisolated var id: String {
        room.id()
    }

    public init(room: MatrixRustSDK.Room) {
        self.room = room
        subscribeRoomInfo()
    }

    @ObservationIgnored private var roomInfoListener: MatrixRustListener<RoomInfo>?

    private func subscribeRoomInfo() {
        roomInfoListener = MatrixRustListener(
            configure: { continuation in
                do {
                    let initialRoomInfo = try await self.room.roomInfo()
                    continuation.yield(initialRoomInfo)
                } catch {
                    Logger.SidebarRoom.error("Failed to fetch initial room info: \(error)")
                }

                let listener = AnonymousRoomInfoListener { roomInfo in
                    continuation.yield(roomInfo)
                }

                return self.room.subscribeToRoomInfoUpdates(listener: listener)
            },
            onElement: { [weak self] roomInfo in
                self?.roomInfo = roomInfo
            }
        )
    }
}

final class AnonymousRoomInfoListener: RoomInfoListener {
    let callback: @Sendable (MatrixRustSDK.RoomInfo) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.RoomInfo) -> Void) { self.callback = callback }

    func call(roomInfo: MatrixRustSDK.RoomInfo) {
        callback(roomInfo)
    }
}

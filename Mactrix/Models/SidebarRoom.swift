import Foundation
import MatrixRustSDK

@Observable
public final class SidebarRoom: MatrixRustSDK.Room {
    var roomInfo: RoomInfo?

    public convenience init(room: MatrixRustSDK.Room) {
        self.init(unsafeFromRawPointer: room.uniffiClonePointer())
    }

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
        loadRoomInfo()
    }

    fileprivate func loadRoomInfo() {
        Task {
            do {
                self.roomInfo = try await self.roomInfo()
            } catch {
                print("Failed to load room info: \(error)")
            }
        }
    }
}

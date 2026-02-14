import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class LiveRoom: Identifiable {
    let sidebarRoom: SidebarRoom

    public var typingUserIds: [String] = []
    public var members: [MatrixRustSDK.RoomMember] = []

    @ObservationIgnored private var typingHandle: TaskHandle?

    public nonisolated var room: MatrixRustSDK.Room {
        sidebarRoom.room
    }

    public var roomInfo: MatrixRustSDK.RoomInfo? {
        sidebarRoom.roomInfo
    }

    public nonisolated var id: String {
        sidebarRoom.id
    }

    public init(sidebarRoom: SidebarRoom) {
        self.sidebarRoom = sidebarRoom

        startListening()

        Task {
            do {
                try await syncMembers()
            } catch {
                Logger.liveRoom.error("failed to sync room members: \(error)")
            }
        }
    }

    public convenience init(matrixRoom: MatrixRustSDK.Room) {
        self.init(sidebarRoom: SidebarRoom(room: matrixRoom))
    }

    isolated deinit {
        Logger.matrixClient.info("live room deinit")
    }

    fileprivate func startListening() {
        Logger.matrixClient.info("typing indicator start listening")

        let listener = AsyncSDKListener<[String]>()
        typingHandle = room.subscribeToTypingNotifications(listener: listener)

        Task { [weak self] in
            for await typingUserIds in listener {
                Logger.matrixClient.info("typing indicator updating UI")
                self?.typingUserIds = typingUserIds
            }
        }
    }

    public func syncMembers() async throws {
        let id = self.id
        Logger.liveRoom.debug("syncing members for room: \(id)")

        // Get the locally cached members first
        let membersNoSyncIter = try await room.membersNoSync()
        if let result = membersNoSyncIter.nextChunk(chunkSize: membersNoSyncIter.len()) {
            members = result
            Logger.liveRoom.debug("loaded \(result.count) members locally for room \(id)")
        }

        // Fetch the latest members from the homeserver, this gets the latest member list.
        let memberIter = try await room.members()
        if let result = memberIter.nextChunk(chunkSize: memberIter.len()) {
            members = result
            Logger.liveRoom.debug("synced \(result.count) members for room \(id)")
        }
    }
}

final class AnonymousTypingListener: TypingNotificationsListener {
    let callback: @Sendable ([String]) -> Void
    init(callback: @Sendable @escaping ([String]) -> Void) { self.callback = callback }

    func call(typingUserIds: [String]) {
        Logger.matrixClient.info("typing indicator called from rust")
        callback(typingUserIds)
    }
}

extension LiveRoom: Hashable {
    public nonisolated static func == (lhs: LiveRoom, rhs: LiveRoom) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension LiveRoom: Models.Room {
    public nonisolated var displayName: String? {
        room.displayName()
    }

    public nonisolated var topic: String? {
        room.topic()
    }

    public nonisolated var encryptionState: Models.EncryptionState {
        room.encryptionState().asModel
    }
}

import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class LiveRoom: Identifiable {
    let sidebarRoom: SidebarRoom

    public var typingUserIds: [String] = []
    public var fetchedMembers: [MatrixRustSDK.RoomMember]?

    @ObservationIgnored private var typingListener: MatrixRustListener<[String]>?

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
    }

    public convenience init(matrixRoom: MatrixRustSDK.Room) {
        self.init(sidebarRoom: SidebarRoom(room: matrixRoom))
    }

    isolated deinit {
        Logger.matrixClient.info("live room deinit")
    }

    fileprivate func startListening() {
        Logger.matrixClient.info("typing indicator start listening")

        typingListener = MatrixRustListener(
            configure: { continuation in
                let listener = AnonymousTypingListener { typingUserIds in
                    Logger.matrixClient.info("typing indicator stream yield")
                    continuation.yield(typingUserIds)
                }

                continuation.onTermination = { _ in
                    Logger.matrixClient.info("typing indicator continuation terminated")
                }

                return self.room.subscribeToTypingNotifications(listener: listener)
            },
            onElement: { typingUserIds in
                Logger.matrixClient.info("typing indicator updating UI")
                self.typingUserIds = typingUserIds
            }
        )
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
    public func syncMembers() async throws {
        // guard not already synced
        guard fetchedMembers == nil else { return }

        let id = self.id
        Logger.liveRoom.debug("syncing members for room: \(id)")

        let memberIter = try await room.members()
        var result = [MatrixRustSDK.RoomMember]()
        while let memberChunk = memberIter.nextChunk(chunkSize: 1000) {
            result.append(contentsOf: memberChunk)
        }
        fetchedMembers = result

        Logger.liveRoom.debug("synced \(result.count) members")
    }

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

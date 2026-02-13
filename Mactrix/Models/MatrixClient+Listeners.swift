import Foundation
import MatrixRustSDK
import OSLog

extension MatrixClient: RoomListEntriesListener {
    nonisolated func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        Task { @MainActor in
            for update in roomEntriesUpdate {
                switch update {
                case let .append(values):
                    rooms.append(contentsOf: values.map(SidebarRoom.init(room:)))
                case .clear:
                    rooms.removeAll()
                case let .pushFront(room):
                    rooms.insert(SidebarRoom(room: room), at: 0)
                case let .pushBack(room):
                    rooms.append(SidebarRoom(room: room))
                case .popFront:
                    rooms.removeFirst()
                case .popBack:
                    rooms.removeLast()
                case let .insert(index, room):
                    rooms.insert(SidebarRoom(room: room), at: Int(index))
                case let .set(index, room):
                    rooms[Int(index)] = SidebarRoom(room: room)
                case let .remove(index):
                    rooms.remove(at: Int(index))
                case let .truncate(length):
                    rooms.removeSubrange(Int(length) ..< rooms.count)
                case let .reset(values: values):
                    rooms = values.map(SidebarRoom.init(room:))
                }
            }
        }
    }
}

final class AnonymousSyncServiceStateObserver: SyncServiceStateObserver {
    let callback: @Sendable (MatrixRustSDK.SyncServiceState) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.SyncServiceState) -> Void) { self.callback = callback }

    func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        callback(state)
    }
}

final class AnonymousVerificationStateListener: VerificationStateListener {
    let callback: @Sendable (MatrixRustSDK.VerificationState) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.VerificationState) -> Void) { self.callback = callback }

    func onUpdate(status: MatrixRustSDK.VerificationState) {
        callback(status)
    }
}

final class AnonymousRoomListServiceStateListener: RoomListServiceStateListener {
    let callback: @Sendable (MatrixRustSDK.RoomListServiceState) -> Void
    init(callback: @Sendable @escaping (MatrixRustSDK.RoomListServiceState) -> Void) { self.callback = callback }

    func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        callback(state)
    }
}

final class AnonymousRoomListServiceSyncIndicatorListener: RoomListServiceSyncIndicatorListener {
    let callback: @Sendable (RoomListServiceSyncIndicator) -> Void
    init(callback: @Sendable @escaping (RoomListServiceSyncIndicator) -> Void) { self.callback = callback }

    func onUpdate(syncIndicator: RoomListServiceSyncIndicator) {
        callback(syncIndicator)
    }
}

enum ClientDelegateEvent {
    case didReceiveAuthError(isSoftLogout: Bool)
}

final class AnonymousClientDelegate: ClientDelegate {
    let callback: @Sendable (ClientDelegateEvent) -> Void
    init(callback: @Sendable @escaping (ClientDelegateEvent) -> Void) { self.callback = callback }

    func didReceiveAuthError(isSoftLogout: Bool) {
        callback(.didReceiveAuthError(isSoftLogout: isSoftLogout))
    }
}

final class AnonymousIgnoredUsersListener: IgnoredUsersListener {
    let callback: @Sendable ([String]) -> Void
    init(callback: @Sendable @escaping ([String]) -> Void) { self.callback = callback }

    func call(ignoredUserIds: [String]) {
        callback(ignoredUserIds)
    }
}

extension MatrixClient: SessionVerificationControllerDelegate {
    nonisolated func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationRequest")
            sessionVerificationRequest = details
        }
    }

    nonisolated func didAcceptVerificationRequest() {
        Logger.matrixClient.debug("session verification: didAcceptVerificationRequest")
    }

    nonisolated func didStartSasVerification() {
        Logger.matrixClient.debug("session verification: didStartSasVerification")
    }

    nonisolated func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationData")
            sessionVerificationData = data
        }
    }

    nonisolated func didFail() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFail")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didCancel() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didCancel")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didFinish() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFinish")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }
}

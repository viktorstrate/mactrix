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

extension MatrixClient: SyncServiceStateObserver {
    nonisolated func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        Task { @MainActor in
            syncState = state
        }
    }
}

extension MatrixClient: VerificationStateListener {
    nonisolated func onUpdate(status: MatrixRustSDK.VerificationState) {
        Task { @MainActor in
            verificationState = status
        }
    }
}

extension MatrixClient: RoomListServiceStateListener {
    nonisolated func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        Task { @MainActor in
            roomListServiceState = state
        }
    }
}

extension MatrixClient: RoomListServiceSyncIndicatorListener {
    nonisolated func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        Task { @MainActor in
            showRoomSyncIndicator = syncIndicator
        }
    }
}

extension MatrixClient: MatrixRustSDK.ClientDelegate {
    nonisolated func didReceiveAuthError(isSoftLogout: Bool) {
        Task { @MainActor in
            Logger.matrixClient.debug("did receive auth error: soft logout \(isSoftLogout, privacy: .public)")
            if !isSoftLogout {
                authenticationFailed = true
            }
        }
    }
}

extension MatrixClient: MatrixRustSDK.IgnoredUsersListener {
    nonisolated func call(ignoredUserIds: [String]) {
        Task { @MainActor in
            Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
            self.ignoredUserIds = ignoredUserIds
        }
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

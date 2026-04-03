import Foundation
import MatrixRustSDK
import OSLog

extension MatrixClient {
    func updateRoomEntries(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        for update in roomEntriesUpdate {
            switch update {
            case let .append(values):
                self.rooms.append(contentsOf: values.map(SidebarRoom.init(room:)))
            case .clear:
                self.rooms.removeAll()
            case let .pushFront(room):
                self.rooms.insert(SidebarRoom(room: room), at: 0)
            case let .pushBack(room):
                self.rooms.append(SidebarRoom(room: room))
            case .popFront:
                self.rooms.removeFirst()
            case .popBack:
                self.rooms.removeLast()
            case let .insert(index, room):
                self.rooms.insert(SidebarRoom(room: room), at: Int(index))
            case let .set(index, room):
                let existing = self.rooms[Int(index)]
                if existing.id == room.id() {
                    existing.updateRoom(room)
                } else {
                    self.rooms[Int(index)] = SidebarRoom(room: room)
                }
            case let .remove(index):
                self.rooms.remove(at: Int(index))
            case let .truncate(length):
                self.rooms.removeSubrange(Int(length) ..< self.rooms.count)
            case let .reset(values: values):
                let existingById = Dictionary(self.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.rooms = values.map { room in
                    if let existing = existingById[room.id()] {
                        existing.updateRoom(room)
                        return existing
                    }
                    return SidebarRoom(room: room)
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
    nonisolated func onBackgroundTaskErrorReport(taskName: String, error: MatrixRustSDK.BackgroundTaskFailureReason) {
        Logger.matrixClient.error("onBackgroundTaskErrorReport taskName: \(taskName)")
    }

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

import Foundation
import MatrixRustSDK
import OSLog

final class AnonymousRoomListEntriesListener: RoomListEntriesListener {
    let callback: @Sendable ([MatrixRustSDK.RoomListEntriesUpdate]) -> Void
    init(callback: @Sendable @escaping ([MatrixRustSDK.RoomListEntriesUpdate]) -> Void) { self.callback = callback }

    func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomListEntriesUpdate]) {
        callback(roomEntriesUpdate)
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

import Foundation
import MatrixRustSDK
import UserNotifications

extension MatrixClient: RoomListEntriesListener {
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
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

extension MatrixClient: SyncServiceStateObserver {
    func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        syncState = state
    }
}

extension MatrixClient: VerificationStateListener {
    func onUpdate(status: MatrixRustSDK.VerificationState) {
        verificationState = status
    }
}

extension MatrixClient: RoomListServiceStateListener {
    func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        roomListServiceState = state
    }
}

extension MatrixClient: RoomListServiceSyncIndicatorListener {
    func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        showRoomSyncIndicator = syncIndicator
    }
}

extension MatrixClient: SessionVerificationControllerDelegate {
    func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        print("session verification: didReceiveVerificationRequest")
        sessionVerificationRequest = details
    }

    func didAcceptVerificationRequest() {
        print("session verification: didAcceptVerificationRequest")
    }

    func didStartSasVerification() {
        print("session verification: didStartSasVerification")
    }

    func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        print("session verification: didReceiveVerificationData")
        sessionVerificationData = data
    }

    func didFail() {
        print("session verification: didFail")
        sessionVerificationRequest = nil
        sessionVerificationData = nil
    }

    func didCancel() {
        print("session verification: didCancel")
        sessionVerificationRequest = nil
        sessionVerificationData = nil
    }

    func didFinish() {
        print("session verification: didFinish")
        sessionVerificationRequest = nil
        sessionVerificationData = nil
    }
}

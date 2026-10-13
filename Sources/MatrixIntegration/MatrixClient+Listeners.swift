import AppKit
import Foundation
import MatrixRustSDK
import OSLog
import Observation

extension MatrixClient {
  func updateRoomEntries(roomEntriesUpdate: [RoomListEntriesUpdate]) {
    let previousRoomIDs = Set(rooms.map(\.id))
    for update in roomEntriesUpdate {
      switch update {
      case .append(let values):
        self.rooms.append(contentsOf: values.map(SidebarRoom.init(room:)))
      case .clear:
        self.rooms.removeAll()
      case .pushFront(let room):
        self.rooms.insert(SidebarRoom(room: room), at: 0)
      case .pushBack(let room):
        self.rooms.append(SidebarRoom(room: room))
      case .popFront:
        self.rooms.removeFirst()
      case .popBack:
        self.rooms.removeLast()
      case .insert(let index, let room):
        self.rooms.insert(SidebarRoom(room: room), at: Int(index))
      case .set(let index, let room):
        let existing = self.rooms[Int(index)]
        if existing.id == room.id() {
          existing.updateRoom(room)
        } else {
          self.rooms[Int(index)] = SidebarRoom(room: room)
        }
      case .remove(let index):
        self.rooms.remove(at: Int(index))
      case .truncate(let length):
        self.rooms.removeSubrange(Int(length)..<self.rooms.count)
      case .reset(let values):
        let existingById = Dictionary(
          self.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.rooms = values.map { room in
          if let existing = existingById[room.id()] {
            existing.updateRoom(room)
            return existing
          }
          return SidebarRoom(room: room)
        }
      }
    }
    if Set(rooms.map(\.id)) != previousRoomIDs {
      spaceService?.refreshRoomsWithParents()
    }
  }

  var unreadRoomCount: Int {
    rooms.reduce(0) { count, room in
      guard let info = room.roomInfo else { return count }
      let isUnread =
        info.isMarkedUnread || info.numUnreadNotifications > 0 || info.numUnreadMentions > 0
      return count + (isUnread ? 1 : 0)
    }
  }

  func observeDockIconUnreadCount() {
    let count = withObservationTracking {
      unreadRoomCount
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observeDockIconUnreadCount()
      }
    }

    guard count != lastAppliedDockUnreadCount else { return }
    NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    lastAppliedDockUnreadCount = count
  }
}

extension MatrixClient: SyncServiceStateObserver {
  nonisolated public func onUpdate(state: MatrixRustSDK.SyncServiceState) {
    Task { @MainActor in
      syncState = state
    }
  }
}

extension MatrixClient: VerificationStateListener {
  nonisolated public func onUpdate(status: MatrixRustSDK.VerificationState) {
    Task { @MainActor in
      verificationState = status
    }
  }
}

extension MatrixClient: RoomListServiceStateListener {
  nonisolated public func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
    Task { @MainActor in
      roomListServiceState = state
    }
  }
}

extension MatrixClient: RoomListServiceSyncIndicatorListener {
  nonisolated public func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
    Task { @MainActor in
      showRoomSyncIndicator = syncIndicator
    }
  }
}

extension MatrixClient: MatrixRustSDK.ClientDelegate {
  nonisolated public func onBackgroundTaskErrorReport(
    taskName: String, error: MatrixRustSDK.BackgroundTaskFailureReason
  ) {
    Logger.matrixClient.error("onBackgroundTaskErrorReport taskName: \(taskName)")
  }

  nonisolated public func didReceiveAuthError(isSoftLogout: Bool) {
    Task { @MainActor in
      Logger.matrixClient.debug(
        "did receive auth error: soft logout \(isSoftLogout, privacy: .public)")
      if !isSoftLogout {
        authenticationFailed = true
      }
    }
  }
}

extension MatrixClient: MatrixRustSDK.IgnoredUsersListener {
  nonisolated public func call(ignoredUserIds: [String]) {
    Task { @MainActor in
      Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
      self.ignoredUserIds = ignoredUserIds
    }
  }
}

extension MatrixClient: SessionVerificationControllerDelegate {
  nonisolated public func didReceiveVerificationRequest(
    details: MatrixRustSDK.SessionVerificationRequestDetails
  ) {
    Task { @MainActor in
      Logger.matrixClient.debug("session verification: didReceiveVerificationRequest")
      sessionVerificationRequest = details
    }
  }

  nonisolated public func didAcceptVerificationRequest() {
    Logger.matrixClient.debug("session verification: didAcceptVerificationRequest")
  }

  nonisolated public func didStartSasVerification() {
    Logger.matrixClient.debug("session verification: didStartSasVerification")
  }

  nonisolated public func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
    Task { @MainActor in
      Logger.matrixClient.debug("session verification: didReceiveVerificationData")
      sessionVerificationData = data
    }
  }

  nonisolated public func didFail() {
    Task { @MainActor in
      Logger.matrixClient.debug("session verification: didFail")
      sessionVerificationRequest = nil
      sessionVerificationData = nil
    }
  }

  nonisolated public func didCancel() {
    Task { @MainActor in
      Logger.matrixClient.debug("session verification: didCancel")
      sessionVerificationRequest = nil
      sessionVerificationData = nil
    }
  }

  nonisolated public func didFinish() {
    Task { @MainActor in
      Logger.matrixClient.debug("session verification: didFinish")
      sessionVerificationRequest = nil
      sessionVerificationData = nil
    }
  }
}

import Foundation
import MatrixRustSDK
import OSLog

@MainActor
protocol RoomSubscriptionService: AnyObject {
  func setRoomSubscriptions(roomIds: [String]) async throws
}

extension RoomListService: RoomSubscriptionService {}

/// Account-scoped ownership of the SDK's complete room-subscription set.
@MainActor
final class RoomSubscriptions {
  private var registrations: [UUID: String] = [:]
  private var service: (any RoomSubscriptionService)?

  private var appliedRoomIDs: Set<String>?
  private var updateTask: Task<Void, Never>?
  private var isActive = true

  func register(roomID: String) -> RoomSubscriptionToken {
    let id = UUID()
    if isActive {
      registrations[id] = roomID
      scheduleUpdate()
    }
    return RoomSubscriptionToken(id: id, subscriptions: self)
  }

  fileprivate func release(_ id: UUID) {
    guard registrations.removeValue(forKey: id) != nil else { return }
    scheduleUpdate()
  }

  func setService(_ service: (any RoomSubscriptionService)?) {
    guard isActive else { return }
    self.service = service

    appliedRoomIDs = nil
    scheduleUpdate()
  }

  /// Drain through the same writer, so an in-flight update cannot re-subscribe after logout.
  func invalidate() async {
    isActive = false
    registrations.removeAll()
    await synchronize()
  }

  func synchronize() async {
    scheduleUpdate()
    await updateTask?.value
  }

  private func scheduleUpdate() {
    guard updateTask == nil, service != nil else { return }
    updateTask = Task { [weak self] in
      await self?.applySubscriptions()
    }
  }

  private func applySubscriptions() async {
    defer { updateTask = nil }
    while let service {
      let desired = Set(registrations.values)
      guard appliedRoomIDs != desired else {
        if !isActive { self.service = nil }
        return
      }

      do {
        try await service.setRoomSubscriptions(roomIds: desired.sorted())
      } catch {
        Logger.matrixClient.error("Failed to update room subscriptions: \(error)")
        // Keep the desired state for a later retry, without a busy retry loop.
        guard service === self.service else { continue }
        appliedRoomIDs = nil
        if desired != Set(registrations.values) { continue }
        if !isActive { self.service = nil }
        return
      }
      guard service === self.service else { continue }
      appliedRoomIDs = desired
    }
  }
}

/// Retaining a registration keeps its room subscribed. The coordinator never owns this token.
@MainActor
final class RoomSubscriptionToken {
  private let id: UUID
  private let subscriptions: RoomSubscriptions

  fileprivate init(id: UUID, subscriptions: RoomSubscriptions) {
    self.id = id
    self.subscriptions = subscriptions
  }

  isolated deinit {
    subscriptions.release(id)
  }
}

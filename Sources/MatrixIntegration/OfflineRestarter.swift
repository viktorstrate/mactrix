/// Restarts an offline account's sync a few times, then leaves reconnecting to the sync service's
/// offline mode.
///
/// The sync service's offline mode only reconnects once a reachability check succeeds, and a
/// check on a connection that went dead when the network changed hangs until it times out,
/// keeping the account offline for a minute or more. A restart cancels that check and tries again
/// at once. A homeserver that's down or unreachable can stay that way for a long time, though, and
/// offline mode keeps checking on its own, so restarting for longer would only spend battery.
@MainActor
final class OfflineRestarter {
  /// How long to wait before each restart. Each wait is shortened by up to half at random, so
  /// clients of a homeserver that went down don't all retry at once.
  static let delays: [Duration] = [2, 4, 8, 16, 30].map { .seconds($0) }

  /// The waits used instead of `delays` in Low Power Mode or on a connection that saves data,
  /// where each restart's new connection and full sync request cost more.
  static let savingDelays: [Duration] = [5, 20].map { .seconds($0) }

  private let canRestart: @MainActor () -> Bool
  private let isSavingPower: @MainActor () -> Bool
  private let restart: @MainActor () async -> Void
  private let sleep: @MainActor (Duration) async -> Void
  private let jitter: @MainActor () -> Double
  private var task: Task<Void, Never>?

  /// - Parameters:
  ///   - canRestart: Whether the account is still offline and a restart could help. Checked
  ///     after each wait; the round ends once it's `false`.
  ///   - isSavingPower: Whether to use `savingDelays`. Checked before and after each wait, so
  ///     turning it on partway through cuts the round short.
  ///   - restart: Restarts sync.
  ///   - sleep: Waits for the given time. Replaced in tests.
  ///   - jitter: The fraction of each delay to wait, from 0.5 to 1. Replaced in tests.
  init(
    canRestart: @escaping @MainActor () -> Bool,
    isSavingPower: @escaping @MainActor () -> Bool,
    restart: @escaping @MainActor () async -> Void,
    sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
    jitter: @escaping @MainActor () -> Double = { .random(in: 0.5...1) }
  ) {
    self.canRestart = canRestart
    self.isSavingPower = isSavingPower
    self.restart = restart
    self.sleep = sleep
    self.jitter = jitter
  }

  /// Starts a round of restarts, unless one is already going.
  func start() {
    guard task == nil else { return }
    task = Task { [weak self] in
      await self?.run()
      if !Task.isCancelled {
        self?.task = nil
      }
    }
  }

  /// Ends the current round.
  func cancel() {
    task?.cancel()
  }

  private var currentDelays: [Duration] { isSavingPower() ? Self.savingDelays : Self.delays }

  /// Runs one round of restarts, returning when it ends.
  func run() async {
    var restarts = 0
    while restarts < currentDelays.count {
      await sleep(currentDelays[restarts] * jitter())
      // Saving power may have turned on during the wait, leaving no restarts in this round.
      guard !Task.isCancelled, restarts < currentDelays.count, canRestart() else { return }
      await restart()
      restarts += 1
    }
  }
}

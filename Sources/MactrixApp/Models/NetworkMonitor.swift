import Foundation
import MatrixIntegration
import Network
import OSLog

/// Reports the Mac's network connection: whether there is one and what it allows, and when it
/// comes back or switches to another interface.
///
/// The sync service's offline mode only notices the network is back on its next scheduled check,
/// which backs off to several seconds apart. Restarting sync on a reconnect reconnects at once.
@MainActor
final class NetworkMonitor {
  private let monitor = NWPathMonitor()
  private var lastPath: NWPath?

  /// Starts reporting network changes.
  ///
  /// - Parameters:
  ///   - onConditionsChange: Called with the connection's conditions, whenever they change.
  ///   - onReconnect: Called each time the network comes back or switches interface.
  init(
    onConditionsChange: @escaping @MainActor (NetworkConditions) -> Void,
    onReconnect: @escaping @MainActor () -> Void
  ) {
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        let previous = self.lastPath
        self.lastPath = path
        let conditions = Self.conditions(of: path)
        if previous.map(Self.conditions(of:)) != conditions {
          onConditionsChange(conditions)
        }
        guard let previous, Self.isReconnect(from: previous, to: path) else { return }
        Logger.matrixClient.info(
          "Network came back on \(path.availableInterfaces.map(\.name), privacy: .public)")
        onReconnect()
      }
    }
    monitor.start(queue: DispatchQueue(label: "Mactrix.NetworkMonitor"))
  }

  deinit {
    monitor.cancel()
  }

  nonisolated static func conditions(of path: NWPath) -> NetworkConditions {
    NetworkConditions(
      isAvailable: path.status == .satisfied, isExpensive: path.isExpensive,
      isConstrained: path.isConstrained)
  }

  /// Whether going from `previous` to `path` means requests that failed may work now: the
  /// network came back, or it moved to other interfaces, such as from Wi-Fi to Ethernet.
  nonisolated static func isReconnect(from previous: NWPath, to path: NWPath) -> Bool {
    guard path.status == .satisfied else { return false }
    return previous.status != .satisfied
      || previous.availableInterfaces.map(\.name) != path.availableInterfaces.map(\.name)
  }
}

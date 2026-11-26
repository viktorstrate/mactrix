import Foundation
import Network
import OSLog

/// Reports when the Mac's network comes back, or switches to another interface.
///
/// The sync service's offline mode only notices the network is back on its next scheduled check,
/// which backs off to several seconds apart. Restarting sync when this fires reconnects at once.
@MainActor
final class NetworkMonitor {
  private let monitor = NWPathMonitor()
  private var lastPath: NWPath?

  /// Starts calling `onReconnect` each time the network comes back or switches interface.
  init(onReconnect: @escaping @MainActor () -> Void) {
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        let previous = self.lastPath
        self.lastPath = path
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

  /// Whether going from `previous` to `path` means requests that failed may work now: the
  /// network came back, or it moved to other interfaces, such as from Wi-Fi to Ethernet.
  nonisolated static func isReconnect(from previous: NWPath, to path: NWPath) -> Bool {
    guard path.status == .satisfied else { return false }
    return previous.status != .satisfied
      || previous.availableInterfaces.map(\.name) != path.availableInterfaces.map(\.name)
  }
}

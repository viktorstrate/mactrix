import Darwin
import OSLog

/// The number of files the process may have open at once.
///
/// Each signed-in account keeps dozens of SQLite files and sockets open, so the default soft
/// limit of 256 leaves little room for several accounts.
public enum OpenFileLimit {
  /// The soft limit to raise to, well below the kernel's `OPEN_MAX` of 10240.
  static let target: rlim_t = 4096

  /// Raises the soft limit to `target`, or as far as the hard limit allows. Never lowers it.
  public static func raise() {
    var limit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
      Logger.matrixClient.error("Failed to read the open file limit: errno \(errno)")
      return
    }
    guard let soft = raisedSoftLimit(current: limit.rlim_cur, hard: limit.rlim_max) else { return }

    let previous = limit.rlim_cur
    limit.rlim_cur = soft
    if setrlimit(RLIMIT_NOFILE, &limit) == 0 {
      Logger.matrixClient.info("Raised the open file limit from \(previous) to \(soft)")
    } else {
      Logger.matrixClient.error("Failed to raise the open file limit: errno \(errno)")
    }
  }

  /// The soft limit to set, or `nil` if `current` is already at least `target` or the hard limit.
  static func raisedSoftLimit(current: rlim_t, hard: rlim_t, target: rlim_t = target) -> rlim_t? {
    let soft = min(target, hard)
    return soft > current ? soft : nil
  }
}

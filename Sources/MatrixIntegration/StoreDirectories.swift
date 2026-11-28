import Foundation
import OSLog

/// Locations of the per-account SQLite stores, which are named by `storeID`.
enum StoreDirectories {
  static let appDirectoryName = "dk.qpqp.mactrix"

  static var dataRoot: URL {
    URL.applicationSupportDirectory.appending(component: appDirectoryName)
  }

  static var cachesRoot: URL {
    URL.cachesDirectory.appending(component: appDirectoryName)
  }

  static func data(for storeID: String) -> URL {
    dataRoot.appending(component: storeID)
  }

  static func caches(for storeID: String) -> URL {
    cachesRoot.appending(component: storeID)
  }

  /// Deletes store directories that belong to no account, such as those created for a login
  /// that was abandoned.
  ///
  /// Only directories named by a UUID (as created for new stores) and created before `cutoff`
  /// are removed. Returns the removed directories.
  @discardableResult
  static func removeOrphans(
    in roots: [URL], keeping storeIDs: Set<String>, createdBefore cutoff: Date,
    fileManager: FileManager = .default
  ) -> [URL] {
    var removed: [URL] = []
    for root in roots {
      let children =
        (try? fileManager.contentsOfDirectory(
          at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
      for child in children {
        let name = child.lastPathComponent
        guard UUID(uuidString: name) != nil, !storeIDs.contains(name) else { continue }
        let values = try? child.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
        guard values?.isDirectory == true,
          let created = values?.creationDate, created < cutoff
        else { continue }
        do {
          try fileManager.removeItem(at: child)
          removed.append(child)
          Logger.matrixClient.info("Removed orphaned store \(name)")
        } catch {
          Logger.matrixClient.error("Failed to remove orphaned store \(name): \(error)")
        }
      }
    }
    return removed
  }
}

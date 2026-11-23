import Foundation
import Testing

@testable import MatrixIntegration

struct StoreDirectoriesTests {
  let root: URL
  let fileManager = FileManager.default

  init() throws {
    root = fileManager.temporaryDirectory.appending(component: "StoreDirectoriesTests-\(UUID())")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func makeDirectory(_ name: String, createdAt date: Date) throws -> URL {
    let url = root.appending(component: name)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    try fileManager.setAttributes([.creationDate: date], ofItemAtPath: url.path)
    return url
  }

  @Test func removesOnlyOldUnreferencedStores() throws {
    let old = Date.now.addingTimeInterval(-3600)
    let kept = UUID().uuidString
    let orphan = UUID().uuidString
    let inProgress = UUID().uuidString

    let keptURL = try makeDirectory(kept, createdAt: old)
    let orphanURL = try makeDirectory(orphan, createdAt: old)
    let inProgressURL = try makeDirectory(inProgress, createdAt: .now)
    let unrelatedURL = try makeDirectory("not-a-store", createdAt: old)

    let removed = StoreDirectories.removeOrphans(
      in: [root], keeping: [kept], createdBefore: Date.now.addingTimeInterval(-600))

    #expect(removed.map(\.lastPathComponent) == [orphan])
    #expect(fileManager.fileExists(atPath: keptURL.path))
    #expect(!fileManager.fileExists(atPath: orphanURL.path))
    #expect(fileManager.fileExists(atPath: inProgressURL.path))
    #expect(fileManager.fileExists(atPath: unrelatedURL.path))
  }

  @Test func missingRootIsIgnored() {
    let removed = StoreDirectories.removeOrphans(
      in: [root.appending(component: "missing")], keeping: [], createdBefore: .now)
    #expect(removed.isEmpty)
  }
}

import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MactrixApp

@MainActor
struct ChatComposerStateTests {
  @Test func attachmentsAppendInOrderAndDeduplicate() {
    let composer = ChatComposerState()
    let first = attachment(filename: "first.txt", identity: .absolutePath("/one/first.txt"))
    let duplicate = attachment(filename: "copy.txt", identity: .absolutePath("/one/first.txt"))
    let second = attachment(filename: "second.txt", identity: .absolutePath("/two/second.txt"))

    composer.addAttachments([first, duplicate, second])
    composer.addAttachments([first])

    #expect(composer.attachments.map(\.id) == [first.id, second.id])
  }

  @Test func differentFilesWithSameFilenameRemain() {
    let composer = ChatComposerState()
    let first = attachment(filename: "report.txt", identity: .absolutePath("/one/report.txt"))
    let second = attachment(filename: "report.txt", identity: .absolutePath("/two/report.txt"))

    composer.addAttachments([first, second])

    #expect(composer.attachments.map(\.id) == [first.id, second.id])
  }

  @Test func removingAttachmentPreservesOtherComposerState() {
    let composer = ChatComposerState()
    let first = attachment(filename: "first.txt", identity: .absolutePath("/first.txt"))
    let second = attachment(filename: "second.txt", identity: .absolutePath("/second.txt"))
    composer.text = "caption"
    composer.addAttachments([first, second])

    composer.removeAttachment(id: first.id)

    #expect(composer.text == "caption")
    #expect(composer.attachments.map(\.id) == [second.id])
  }

  @Test func removalCleansOnlyAppOwnedTemporaryFiles() throws {
    let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MactrixComposerAttachments/state-test-\(UUID().uuidString).txt")
    try FileManager.default.createDirectory(
      at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("temporary".utf8).write(to: temporaryURL)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    let externalURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try Data("external".utf8).write(to: externalURL)
    defer { try? FileManager.default.removeItem(at: externalURL) }

    let owned = attachment(
      url: temporaryURL, filename: "temporary.txt", ownership: .appOwnedTemporaryFile,
      identity: .absolutePath(temporaryURL.path))
    let external = attachment(
      url: externalURL, filename: "external.txt", ownership: .externalUserFile,
      identity: .absolutePath(externalURL.path))
    let composer = ChatComposerState()
    composer.addAttachments([owned, external])

    composer.removeAttachment(id: owned.id)
    composer.removeAttachment(id: external.id)

    #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
    #expect(FileManager.default.fileExists(atPath: externalURL.path))
  }

  @Test func canSendReflectsTextAndAttachments() {
    let composer = ChatComposerState()
    #expect(!composer.canSend)

    composer.text = "text"
    #expect(composer.canSend)

    composer.text = ""
    composer.addAttachments([
      attachment(filename: "file.txt", identity: .absolutePath("/file.txt"))
    ])
    #expect(composer.canSend)
  }

  @Test func resetClearsTextAndAttachments() {
    let composer = ChatComposerState()
    composer.text = "caption"
    composer.addAttachments([attachment(filename: "file.txt", identity: .absolutePath("/file.txt"))]
    )

    composer.reset()

    #expect(composer.text.isEmpty)
    #expect(composer.replyTarget == nil)
    #expect(composer.attachments.isEmpty)
  }

  @Test func snapshotSuccessClearsCapturedContentButRetainsLaterChanges() {
    let composer = ChatComposerState()
    let captured = attachment(filename: "captured.txt", identity: .absolutePath("/captured.txt"))
    let later = attachment(filename: "later.txt", identity: .absolutePath("/later.txt"))
    composer.text = "original"
    composer.addAttachments([captured])
    let snapshot = composer.captureSubmission()

    composer.text = "updated"
    composer.addAttachments([later])
    composer.finishSending(snapshot: snapshot)

    #expect(composer.text == "updated")
    #expect(composer.attachments.map(\.id) == [later.id])
  }

  private func attachment(
    url: URL = URL(fileURLWithPath: "/tmp/attachment"),
    filename: String,
    ownership: ComposerAttachment.StorageOwnership = .externalUserFile,
    identity: ComposerAttachment.DeduplicationIdentity
  ) -> ComposerAttachment {
    ComposerAttachment(
      sourceURL: url, filename: filename, contentType: .plainText, byteCount: nil, kind: .file,
      storageOwnership: ownership, deduplicationIdentity: identity)
  }
}

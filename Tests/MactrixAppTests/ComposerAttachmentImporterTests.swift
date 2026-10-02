import AppKit
import Foundation
import Testing

@testable import MactrixApp

struct ComposerAttachmentImporterTests {
  @Test func regularFileIncludesSizeAndMimeMetadata() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("note.txt")
      try Data("hello".utf8).write(to: url)

      let attachment = try await ComposerAttachmentImporter.importFile(at: url)

      #expect(attachment.kind == .file)
      #expect(attachment.byteCount == 5)
      #expect(attachment.mimeType == "text/plain")
      #expect(attachment.storageOwnership == .externalUserFile)
    }
  }

  @Test func imageIncludesDimensionsAndPreview() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("picture.png")
      try pngData(width: 20, height: 10).write(to: url)

      let attachment = try await ComposerAttachmentImporter.importFile(at: url)

      #expect(attachment.kind == .image)
      #expect(attachment.pixelWidth == 20)
      #expect(attachment.pixelHeight == 10)
      #expect(attachment.preview != nil)
    }
  }

  @Test func audioAndVideoClassifyWhenMetadataIsUnavailable() async throws {
    try await withTemporaryDirectory { directory in
      let audioURL = directory.appendingPathComponent("empty.mp3")
      let videoURL = directory.appendingPathComponent("empty.mov")
      try Data().write(to: audioURL)
      try Data().write(to: videoURL)

      let audio = try await ComposerAttachmentImporter.importFile(at: audioURL)
      let video = try await ComposerAttachmentImporter.importFile(at: videoURL)

      #expect(audio.kind == .audio)
      #expect(video.kind == .video)
    }
  }

  @Test func invalidURLsAreRejectedAndBatchImportPreservesValidOrder() async throws {
    try await withTemporaryDirectory { directory in
      let first = directory.appendingPathComponent("first.txt")
      let second = directory.appendingPathComponent("second.txt")
      try Data("first".utf8).write(to: first)
      try Data("second".utf8).write(to: second)
      let missing = directory.appendingPathComponent("missing.txt")

      await #expect(throws: ComposerAttachmentImporter.ImportError.self) {
        try await ComposerAttachmentImporter.importFile(at: directory)
      }
      await #expect(throws: ComposerAttachmentImporter.ImportError.self) {
        try await ComposerAttachmentImporter.importFile(at: URL(string: "https://example.com/file")!)
      }

      let attachments = await ComposerAttachmentImporter.importFiles(at: [first, missing, second])
      #expect(attachments.map(\.filename) == ["first.txt", "second.txt"])
    }
  }

  @Test func canonicalFilesDeduplicateButEqualNamesDoNot() async throws {
    try await withTemporaryDirectory { directory in
      let firstDirectory = directory.appendingPathComponent("one")
      let secondDirectory = directory.appendingPathComponent("two")
      try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
      let first = firstDirectory.appendingPathComponent("same-name.txt")
      let second = secondDirectory.appendingPathComponent("same-name.txt")
      try Data("one".utf8).write(to: first)
      try Data("two".utf8).write(to: second)

      let firstImport = try await ComposerAttachmentImporter.importFile(at: first)
      let sameFileImport = try await ComposerAttachmentImporter.importFile(at: first)
      let secondImport = try await ComposerAttachmentImporter.importFile(at: second)

      #expect(firstImport.deduplicationIdentity == sameFileImport.deduplicationIdentity)
      #expect(firstImport.deduplicationIdentity != secondImport.deduplicationIdentity)
    }
  }

  @Test func symlinkAndTargetDeduplicate() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appendingPathComponent("target.txt")
      let link = directory.appendingPathComponent("link.txt")
      try Data("target".utf8).write(to: target)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

      let targetImport = try await ComposerAttachmentImporter.importFile(at: target)
      let linkImport = try await ComposerAttachmentImporter.importFile(at: link)

      #expect(targetImport.deduplicationIdentity == linkImport.deduplicationIdentity)
    }
  }

  @Test func clipboardImagesAreTemporaryAndCleanupNeverDeletesExternalFiles() async throws {
    let externalDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: externalDirectory) }
    let externalURL = externalDirectory.appendingPathComponent("external.png")
    try pngData(width: 2, height: 2).write(to: externalURL)

    let pngAttachment = try await ComposerAttachmentImporter.importClipboardImage(
      pngData: pngData(width: 4, height: 3), tiffData: nil)
    let tiffAttachment = try await ComposerAttachmentImporter.importClipboardImage(
      pngData: nil, tiffData: tiffData(width: 4, height: 3))

    #expect(pngAttachment.storageOwnership == .appOwnedTemporaryFile)
    #expect(tiffAttachment.storageOwnership == .appOwnedTemporaryFile)
    #expect(FileManager.default.fileExists(atPath: pngAttachment.sourceURL.path))
    #expect(FileManager.default.fileExists(atPath: tiffAttachment.sourceURL.path))

    try ComposerAttachmentImporter.cleanupTemporaryAttachment(pngAttachment)
    try ComposerAttachmentImporter.cleanupTemporaryAttachment(tiffAttachment)
    #expect(!FileManager.default.fileExists(atPath: pngAttachment.sourceURL.path))

    let externalAttachment = try await ComposerAttachmentImporter.importFile(at: externalURL)
    #expect(throws: ComposerAttachmentImporter.ImportError.self) {
      try ComposerAttachmentImporter.cleanupTemporaryAttachment(externalAttachment)
    }
    #expect(FileManager.default.fileExists(atPath: externalURL.path))
  }

  private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func pngData(width: Int, height: Int) throws -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep, let data = rep.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return data
  }

  private func tiffData(width: Int, height: Int) throws -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep, let data = rep.tiffRepresentation else { throw CocoaError(.fileWriteUnknown) }
    return data
  }
}

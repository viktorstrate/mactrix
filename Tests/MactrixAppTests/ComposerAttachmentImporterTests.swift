import AppKit
import CryptoKit
import Foundation
import ImageIO
import MatrixRustSDK
import Testing
import UniformTypeIdentifiers

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

  @Test func genericImageDeclarationRetainsDetectedMIMEType() async throws {
    try await withTemporaryDirectory { directory in
      let bytes = try pngData(width: 20, height: 10)
      let url = directory.appendingPathComponent("extensionless")
      try bytes.write(to: url)
      let file = try await ComposerAttachmentImporter.importFile(
        at: url, typeIdentifier: UTType.image.identifier)
      let data = try await ComposerAttachmentImporter.importData(
        bytes, filename: "extensionless", typeIdentifier: UTType.image.identifier)
      defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(data) }
      for attachment in [file, data] {
        #expect(attachment.contentType == .image)
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.pixelWidth == 20)
        #expect(attachment.pixelHeight == 10)
        #expect(attachment.preview != nil)
      }
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

  @Test func invalidURLsAreRejected() async throws {
    try await withTemporaryDirectory { directory in
      let missing = directory.appendingPathComponent("missing.txt")
      let nonfile = try #require(URL(string: "https://example.com/file"))
      for url in [missing, directory, nonfile] {
        await #expect(throws: ComposerAttachmentImporter.ImportError.self) {
          try await ComposerAttachmentImporter.importFile(at: url)
        }
      }
    }
  }

  @Test func canonicalFilesDeduplicateButEqualNamesDoNot() async throws {
    try await withTemporaryDirectory { directory in
      let firstDirectory = directory.appendingPathComponent("one")
      let secondDirectory = directory.appendingPathComponent("two")
      try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        at: secondDirectory, withIntermediateDirectories: true)
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

  @Test func draftAttachmentsUsePathSourcesAndAvailableMetadata() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = directory.appendingPathComponent("note.txt")
      let imageURL = directory.appendingPathComponent("image.png")
      let audioURL = directory.appendingPathComponent("audio.mp3")
      let videoURL = directory.appendingPathComponent("video.mov")
      try Data("hello".utf8).write(to: fileURL)
      try pngData(width: 20, height: 10).write(to: imageURL)
      try Data().write(to: audioURL)
      try Data().write(to: videoURL)

      let file = try await ComposerAttachmentImporter.importFile(at: fileURL).draftAttachment
      let image = try await ComposerAttachmentImporter.importFile(at: imageURL).draftAttachment
      let audio = try await ComposerAttachmentImporter.importFile(at: audioURL).draftAttachment
      let video = try await ComposerAttachmentImporter.importFile(at: videoURL).draftAttachment

      guard case .file(let info, .file(let path)) = file else {
        Issue.record("Expected file draft")
        return
      }
      #expect(path == fileURL.path)
      let restored = try await ComposerAttachment.restoreDraftAttachment(file)
      #expect(restored.sourceURL == fileURL.standardizedFileURL)
      #expect(info.size == 5)
      guard case .image(let info, .file(let path), _) = image else {
        Issue.record("Expected image draft")
        return
      }
      #expect(path == imageURL.path)
      #expect(info.width == 20)
      #expect(info.height == 10)
      guard case .audio(_, .file(let audioPath)) = audio else {
        Issue.record("Expected audio draft")
        return
      }
      #expect(audioPath == audioURL.path)
      guard case .video(_, .file(let videoPath), _) = video else {
        Issue.record("Expected video draft")
        return
      }
      #expect(videoPath == videoURL.path)
    }
  }

  @Test func draftRestorationRejectsMissingDirectoriesAndRestoresNativeData() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = directory.appendingPathComponent("valid.txt")
      try Data("valid".utf8).write(to: fileURL)

      let restored = try await ComposerAttachment.restoreDraftAttachment(
        .file(
          fileInfo: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil),
          source: .file(filename: fileURL.path))
      )
      #expect(restored.sourceURL == fileURL.standardizedFileURL)
      #expect(restored.storageOwnership == .externalUserFile)

      await #expect(throws: ComposerAttachmentImporter.ImportError.self) {
        try await ComposerAttachment.restoreDraftAttachment(
          .file(
            fileInfo: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil),
            source: .file(filename: directory.path))
        )
      }
      await #expect(throws: ComposerAttachmentImporter.ImportError.self) {
        try await ComposerAttachment.restoreDraftAttachment(
          .file(
            fileInfo: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil),
            source: .file(filename: directory.appendingPathComponent("missing.txt").path)))
      }

      let restoredData = try await ComposerAttachment.restoreDraftAttachment(
        .file(
          fileInfo: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil),
          source: .data(bytes: Data("data".utf8), filename: "data.txt"))
      )
      defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(restoredData) }
      #expect(restoredData.storageOwnership == .appOwnedTemporaryFile)
      #expect(try Data(contentsOf: restoredData.sourceURL) == Data("data".utf8))
    }
  }

  @Test func nativeDraftDataSurvivesSourceDeletionAndPreservesFilename() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("note.txt")
      let bytes = Data("hello".utf8)
      try bytes.write(to: url)
      // This is the source representation returned by the SDK after saving a .file source.
      let draft = DraftAttachment.file(
        fileInfo: FileInfo(
          mimetype: "text/plain", size: 5, thumbnailInfo: nil, thumbnailSource: nil),
        source: .data(bytes: bytes, filename: url.lastPathComponent))
      try FileManager.default.removeItem(at: url)
      let restored = try await ComposerAttachment.restoreDraftAttachment(draft)
      defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(restored) }
      #expect(restored.filename == "note.txt")
      #expect(restored.sourceURL.lastPathComponent == "note.txt")
      #expect(try Data(contentsOf: restored.sourceURL) == bytes)
      #expect(restored.storageOwnership == .appOwnedTemporaryFile)
      let materializedDirectory = restored.sourceURL.deletingLastPathComponent()
      try ComposerAttachmentImporter.cleanupTemporaryAttachment(restored)
      #expect(!FileManager.default.fileExists(atPath: materializedDirectory.path))
    }
  }

  @Test @MainActor func duplicateNativeDraftDataRestoresOnce() async throws {
    let draft = DraftAttachment.file(
      fileInfo: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil),
      source: .data(bytes: Data("hello".utf8), filename: "note.txt"))
    let first = try await ComposerAttachment.restoreDraftAttachment(draft)
    let second = try await ComposerAttachment.restoreDraftAttachment(draft)
    defer {
      try? ComposerAttachmentImporter.cleanupTemporaryAttachment(first)
      try? ComposerAttachmentImporter.cleanupTemporaryAttachment(second)
    }
    let composer = ChatComposerState()
    composer.addAttachments([first, second])
    #expect(composer.attachments.count == 1)
  }

  @Test func clipboardDraftRestorationPreservesTemporaryOwnership() async throws {
    let original = try await ComposerAttachmentImporter.importData(
      pngData(width: 4, height: 3), typeIdentifier: UTType.png.identifier)
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(original) }
    let restored = try await ComposerAttachment.restoreDraftAttachment(
      .image(
        imageInfo: ImageInfo(
          height: 3, width: 4, mimetype: "image/png", size: nil,
          thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil),
        source: .data(bytes: try Data(contentsOf: original.sourceURL), filename: original.filename),
        thumbnailSource: nil))
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(restored) }
    #expect(restored.sourceURL != original.sourceURL)
    #expect(restored.pixelWidth == 4)
    #expect(restored.preview != nil)
    #expect(restored.deduplicationIdentity == original.deduplicationIdentity)
    #expect(restored.storageOwnership == .appOwnedTemporaryFile)
  }

  @Test func clipboardImagesAreTemporaryAndCleanupNeverDeletesExternalFiles() async throws {
    let externalDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: externalDirectory) }
    let externalURL = externalDirectory.appendingPathComponent("external.png")
    try pngData(width: 2, height: 2).write(to: externalURL)

    let pngAttachment = try await ComposerAttachmentImporter.importData(
      pngData(width: 4, height: 3), typeIdentifier: UTType.png.identifier)
    let tiffAttachment = try await ComposerAttachmentImporter.importData(
      tiffData(width: 4, height: 3), typeIdentifier: UTType.tiff.identifier)

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

  @Test func encodedFormatsRemainUnchangedThroughUploadAndDraft() async throws {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 5,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for (format, name) in [
      (NSBitmapImageRep.FileType.png, "image.png"), (.jpeg, "image.jpg"),
      (.tiff, "image.tiff"), (.gif, "image.gif"),
    ] {
      let bytes = try #require(bitmap.representation(using: format, properties: [:]))
      let attachment = try await ComposerAttachmentImporter.importData(bytes, filename: name)
      defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment) }
      #expect(try Data(contentsOf: attachment.sourceURL) == bytes)
      let prepared = try await ComposerMediaPreparation.prepare(
        attachment: attachment, caption: "", replyID: nil)
      guard case .file(let path) = prepared.parameters.source else {
        Issue.record("Expected original file upload source")
        continue
      }
      #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == bytes)
      let restored = try await ComposerAttachment.restoreDraftAttachment(
        .image(
          imageInfo: ImageInfo(
            height: 5, width: 8, mimetype: attachment.mimeType,
            size: UInt64(bytes.count), thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil,
            isAnimated: nil), source: .data(bytes: bytes, filename: name), thumbnailSource: nil))
      defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(restored) }
      #expect(restored.filename == name)
      #expect(restored.mimeType == attachment.mimeType)
      #expect(try Data(contentsOf: restored.sourceURL) == bytes)
    }
  }

  @Test func unknownMimeAndDraftKindSurvivePreparationAndRestoration() async throws {
    let bytes = Data([0, 1, 2, 255])
    let attachment = try await ComposerAttachmentImporter.importData(
      bytes, filename: "binary.unknown", mimeType: "application/x-mactrix-unknown")
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment) }
    #expect(attachment.kind == .file)
    #expect(attachment.mimeType == "application/x-mactrix-unknown")
    let prepared = try await ComposerMediaPreparation.prepare(
      attachment: attachment, caption: "", replyID: nil)
    guard case .file(let info) = prepared.media else {
      Issue.record("Expected generic file")
      return
    }
    #expect(info.mimetype == attachment.mimeType)
    let restored = try await ComposerAttachment.restoreDraftAttachment(
      .file(fileInfo: info, source: .data(bytes: bytes, filename: attachment.filename)))
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(restored) }
    #expect(restored.kind == .file)
    #expect(restored.mimeType == attachment.mimeType)
    #expect(try Data(contentsOf: restored.sourceURL) == bytes)
  }

  @Test func extensionlessImageAndUndecodableImageAreAccepted() async throws {
    let image = try await ComposerAttachmentImporter.importData(
      pngData(width: 1000, height: 600), filename: "no-extension")
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(image) }
    #expect(image.kind == .image)
    #expect(image.mimeType == "image/png")
    #expect(image.pixelWidth == 1000)
    #expect(image.preview != nil)
    let preview = try #require(
      image.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(max(preview.width, preview.height) <= 512)
    let broken = try await ComposerAttachmentImporter.importData(
      Data([1, 2]), filename: "broken.png")
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(broken) }
    #expect(broken.preview == nil)
    let prepared = try await ComposerMediaPreparation.prepare(
      attachment: broken, caption: "", replyID: nil)
    #expect(prepared.attachment.sourceURL == broken.sourceURL)
    let unknown = try await ComposerAttachmentImporter.importData(
      Data([1, 2]), filename: "binary.unknown")
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(unknown) }
    #expect(unknown.mimeType == "application/octet-stream")
  }

  @Test func clipboardTIFFIsNotTranscoded() async throws {
    let bytes = try tiffData(width: 10, height: 5)
    let attachment = try await ComposerAttachmentImporter.importData(
      bytes, typeIdentifier: UTType.tiff.identifier)
    defer { try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment) }
    #expect(attachment.mimeType == "image/tiff")
    #expect(try Data(contentsOf: attachment.sourceURL) == bytes)
  }

  @Test @MainActor func rejectedDuplicateTemporaryCopyIsRemoved() async throws {
    let bytes = Data([1, 2, 3])
    let first = try await ComposerAttachmentImporter.importData(bytes)
    let duplicate = try await ComposerAttachmentImporter.importData(bytes)
    let composer = ChatComposerState()
    composer.addAttachments([first, duplicate])
    #expect(composer.attachments.count == 1)
    #expect(FileManager.default.fileExists(atPath: first.sourceURL.path))
    #expect(!FileManager.default.fileExists(atPath: duplicate.sourceURL.path))
    composer.addAttachments([first])
    #expect(FileManager.default.fileExists(atPath: first.sourceURL.path))
    composer.removeAttachment(id: first.id)
    #expect(!FileManager.default.fileExists(atPath: first.sourceURL.path))
  }

  @Test @MainActor func pasteboardPrefersExistingFileOverImageBytes() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("original.png")
    try pngData(width: 2, height: 2).write(to: url)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let item = NSPasteboardItem()
    item.setData(Data([1, 2]), forType: .png)
    item.setString(url.absoluteString, forType: .fileURL)
    pasteboard.writeObjects([item])
    let inputs = ComposerAttachmentInputAdapter.inputs(from: pasteboard)
    #expect(inputs.count == 1)
    guard case .file(let selected) = try #require(inputs.first) else {
      Issue.record("Expected original file representation")
      return
    }
    #expect(selected == url)
  }

  @Test func preparationRefreshesSizeWithoutReclassifyingAndRejectsDeletedSource() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("custom.bin")
      try Data([1]).write(to: url)
      let attachment = try await ComposerAttachmentImporter.importFile(
        at: url,
        mimeType: "image/x-custom", kind: .image)
      try Data([1, 2, 3]).write(to: url)
      let prepared = try await ComposerMediaPreparation.prepare(
        attachment: attachment, caption: "caption", replyID: nil)
      guard case .image(let info, _) = prepared.media else {
        Issue.record("Expected retained image kind")
        return
      }
      #expect(info.mimetype == "image/x-custom")
      #expect(info.size == 3)
      #expect(prepared.parameters.caption == "caption")
      try FileManager.default.removeItem(at: url)
      await #expect(throws: (any Error).self) {
        try await ComposerMediaPreparation.prepare(
          attachment: attachment, caption: "", replyID: nil)
      }
    }
  }

  private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func pngData(width: Int, height: Int) throws -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
    )
    guard let rep, let data = rep.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return data
  }

  private func tiffData(width: Int, height: Int) throws -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
    )
    guard let rep, let data = rep.tiffRepresentation else { throw CocoaError(.fileWriteUnknown) }
    return data
  }
}

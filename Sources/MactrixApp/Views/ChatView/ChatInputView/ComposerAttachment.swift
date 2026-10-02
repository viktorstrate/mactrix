import AppKit
import Foundation
import MatrixRustSDK
import UniformTypeIdentifiers

struct ComposerAttachment: Identifiable {
  enum Kind: Sendable {
    case image
    case video
    case audio
    case file
  }

  enum StorageOwnership: Sendable {
    case externalUserFile
    case appOwnedTemporaryFile
  }

  enum DeduplicationIdentity: Hashable, Sendable {
    case fileSystemResourceIdentifier(String)
    case canonicalURL(String)
    case absolutePath(String)
    case contentDigest(String)
  }

  let id: UUID
  let sourceURL: URL
  let filename: String
  let contentType: UTType
  let byteCount: Int64?
  let kind: Kind
  let storageOwnership: StorageOwnership
  let deduplicationIdentity: DeduplicationIdentity
  let pixelWidth: Int?
  let pixelHeight: Int?
  let duration: TimeInterval?
  let preview: NSImage?

  var mimeType: String? {
    contentType.preferredMIMEType
  }

  init(
    id: UUID = UUID(),
    sourceURL: URL,
    filename: String,
    contentType: UTType,
    byteCount: Int64?,
    kind: Kind,
    storageOwnership: StorageOwnership,
    deduplicationIdentity: DeduplicationIdentity,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    duration: TimeInterval? = nil,
    preview: NSImage? = nil
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.filename = filename
    self.contentType = contentType
    self.byteCount = byteCount
    self.kind = kind
    self.storageOwnership = storageOwnership
    self.deduplicationIdentity = deduplicationIdentity
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.duration = duration
    self.preview = preview
  }
}

extension ComposerAttachment {

  var draftAttachment: DraftAttachment {
    // The SDK reads this file into its local draft store and returns .data when loading.
    let source = UploadSource.file(filename: sourceURL.path)
    let size = byteCount.flatMap { $0 >= 0 ? UInt64($0) : nil }

    switch kind {
    case .audio:
      return .audio(
        audioInfo: AudioInfo(duration: duration, size: size, mimetype: mimeType), source: source)
    case .file:
      return .file(
        fileInfo: FileInfo(
          mimetype: mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil), source: source)
    case .image:
      return .image(
        imageInfo: ImageInfo(
          height: pixelHeight.map(UInt64.init), width: pixelWidth.map(UInt64.init),
          mimetype: mimeType,
          size: size, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil),
        source: source, thumbnailSource: nil)
    case .video:
      return .video(
        videoInfo: VideoInfo(
          duration: duration, height: pixelHeight.map(UInt64.init),
          width: pixelWidth.map(UInt64.init),
          mimetype: mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil),
        source: source, thumbnailSource: nil)
    }
  }

  static func restoreDraftAttachment(_ draftAttachment: DraftAttachment) async throws
    -> ComposerAttachment
  {
    let source: UploadSource
    switch draftAttachment {
    case .audio(_, let attachmentSource), .file(_, let attachmentSource),
      .image(_, let attachmentSource, _), .video(_, let attachmentSource, _):
      source = attachmentSource
    }

    switch source {
    case .file(let filename):
      guard !filename.isEmpty, (filename as NSString).isAbsolutePath else {
        throw ComposerAttachmentImporter.ImportError.invalidDraftSource(filename)
      }
      return try await ComposerAttachmentImporter.importFile(at: URL(fileURLWithPath: filename))
    case .data(let bytes, let filename):
      return try await ComposerAttachmentImporter.importDraftData(bytes, filename: filename)
    }
  }
}

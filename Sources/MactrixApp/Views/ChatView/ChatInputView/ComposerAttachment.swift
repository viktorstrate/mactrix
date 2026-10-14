import AppKit
import Foundation
import MatrixRustSDK
import UniformTypeIdentifiers

struct ComposerAttachment: Identifiable {
  enum Kind: Equatable, Sendable {
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

  let mimeType: String

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
    preview: NSImage? = nil,
    mimeType: String? = nil
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.filename = filename
    self.contentType = contentType
    self.mimeType = mimeType ?? contentType.preferredMIMEType ?? "application/octet-stream"
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
    let kind: Kind
    let mimeType: String?
    let width: Int?
    let height: Int?
    let duration: TimeInterval?
    switch draftAttachment {
    case .audio(let info, let attachmentSource):
      source = attachmentSource
      kind = .audio
      mimeType = info.mimetype
      width = nil
      height = nil
      duration = info.duration
    case .file(let info, let attachmentSource):
      source = attachmentSource
      kind = .file
      mimeType = info.mimetype
      width = nil
      height = nil
      duration = nil
    case .image(let info, let attachmentSource, _):
      source = attachmentSource
      kind = .image
      mimeType = info.mimetype
      width = info.width.flatMap(Int.init(exactly:))
      height = info.height.flatMap(Int.init(exactly:))
      duration = nil
    case .video(let info, let attachmentSource, _):
      source = attachmentSource
      kind = .video
      mimeType = info.mimetype
      width = info.width.flatMap(Int.init(exactly:))
      height = info.height.flatMap(Int.init(exactly:))
      duration = info.duration
    }
    let imported: ComposerAttachment
    switch source {
    case .file(let filename):
      guard !filename.isEmpty, (filename as NSString).isAbsolutePath else {
        throw ComposerAttachmentImporter.ImportError.invalidDraftSource(filename)
      }
      imported = try await ComposerAttachmentImporter.importFile(
        at: URL(fileURLWithPath: filename), mimeType: mimeType, kind: kind)
    case .data(let bytes, let filename):
      imported = try await ComposerAttachmentImporter.importData(
        bytes, filename: filename, mimeType: mimeType, kind: kind)
    }
    return ComposerAttachment(
      id: imported.id, sourceURL: imported.sourceURL, filename: imported.filename,
      contentType: imported.contentType, byteCount: imported.byteCount, kind: kind,
      storageOwnership: imported.storageOwnership,
      deduplicationIdentity: imported.deduplicationIdentity,
      pixelWidth: width ?? imported.pixelWidth, pixelHeight: height ?? imported.pixelHeight,
      duration: duration ?? imported.duration, preview: imported.preview,
      mimeType: imported.mimeType)
  }
}

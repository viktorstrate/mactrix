import AppKit
import Foundation
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

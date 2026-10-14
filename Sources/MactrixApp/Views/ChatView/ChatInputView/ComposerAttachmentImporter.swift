import AVFoundation
import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ComposerAttachmentImporter {
  enum ImportError: LocalizedError {
    case notFileURL(URL)
    case notReadableRegularFile(URL)
    case invalidDraftSource(String)
    case cleanupRefused(URL)
    case invalidRawRepresentation

    var errorDescription: String? {
      switch self {
      case .notFileURL(let url): "Attachment URL is not a file URL: \(url)"
      case .notReadableRegularFile(let url):
        "Attachment is not a readable regular file: \(url.path)"
      case .invalidDraftSource(let source): "Draft attachment has an invalid source: \(source)"
      case .cleanupRefused(let url): "Refusing to remove externally-owned attachment: \(url.path)"
      case .invalidRawRepresentation: "No valid image or PDF representation"
      }
    }
  }

  private static let temporaryDirectoryName = "MactrixComposerAttachments"
  private static let previewMaximumPixelSize = 512

  /// Imports one readable regular file. This method performs file and media work off the main actor.
  static func importFile(
    at url: URL,
    storageOwnership: ComposerAttachment.StorageOwnership = .externalUserFile,
    mimeType: String? = nil, typeIdentifier: String? = nil,
    kind: ComposerAttachment.Kind? = nil
  ) async throws -> ComposerAttachment {
    try await Task.detached(priority: .userInitiated) {
      try await inspectFile(
        at: url, storageOwnership: storageOwnership,
        mimeType: mimeType, typeIdentifier: typeIdentifier, kind: kind)
    }.value
  }

  enum Input: Sendable {
    case file(URL)
    case ownedFile(URL)
    case rawRepresentations([RawRepresentation])
  }

  struct RawRepresentation: Sendable {
    let data: Data
    let type: UTType
    var filename: String? = nil
  }

  static func importInput(_ input: Input) async throws -> ComposerAttachment {
    switch input {
    case .file(let url): return try await importFile(at: url)
    case .ownedFile(let url): return try await importOwnedFile(at: url)
    case .rawRepresentations(let representations):
      for representation in representations {
        if let attachment = try? await importRawData(representation) { return attachment }
      }
      throw ImportError.invalidRawRepresentation
    }
  }

  private static let imageTypeIdentifiers = Set(
    CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

  static func supportedRawType(for identifier: String) -> UTType? {
    guard let type = UTType(identifier),
      type == .pdf || (type.conforms(to: .image) && imageTypeIdentifiers.contains(type.identifier)),
      type.preferredMIMEType != nil, type.preferredFilenameExtension != nil
    else { return nil }
    return type
  }

  /// Inspect image headers for representation fallback, without requiring a successful decode.
  /// PDFs are opaque file attachments: encryption or renderability must not gate uploading.
  private static func rawImageSource(_ data: Data, advertisedType: UTType) throws -> CGImageSource?
  {
    guard !data.isEmpty, supportedRawType(for: advertisedType.identifier) != nil else {
      throw ImportError.invalidRawRepresentation
    }
    if advertisedType == .pdf { return nil }
    guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions),
      let identifier = CGImageSourceGetType(source), UTType(identifier as String) == advertisedType
    else { throw ImportError.invalidRawRepresentation }
    return source
  }

  private static func rawFilename(_ filename: String?, type: UTType) throws -> String? {
    guard let filename else { return nil }
    let basename = try sanitizedFilename(filename)
    if UTType(filenameExtension: (basename as NSString).pathExtension) == type { return basename }
    guard let ext = type.preferredFilenameExtension else {
      throw ImportError.invalidRawRepresentation
    }
    return basename + "." + ext
  }

  private static func importRawData(_ representation: RawRepresentation) async throws
    -> ComposerAttachment
  {
    try await Task.detached(priority: .userInitiated) {
      let type = representation.type
      let source = try rawImageSource(representation.data, advertisedType: type)
      return try await storeData(
        representation.data, filename: rawFilename(representation.filename, type: type),
        mimeType: type.preferredMIMEType, typeIdentifier: type.identifier, kind: nil,
        imageSource: source)
    }.value
  }

  /// Stores the selected encoded representation verbatim. Decoding is optional.
  static func importData(
    _ data: Data, filename: String? = nil, mimeType: String? = nil,
    typeIdentifier: String? = nil, kind: ComposerAttachment.Kind? = nil
  ) async throws -> ComposerAttachment {
    try await Task.detached(priority: .userInitiated) {
      let declared = declaredType(mimeType: mimeType, typeIdentifier: typeIdentifier)
      let source =
        shouldInspectImage(declaredType: declared, kind: kind)
        ? CGImageSourceCreateWithData(data as CFData, imageSourceOptions) : nil
      return try await storeData(
        data, filename: filename, mimeType: mimeType, typeIdentifier: typeIdentifier, kind: kind,
        imageSource: source)
    }.value
  }

  private static func storeData(
    _ data: Data, filename: String?, mimeType: String?, typeIdentifier: String?,
    kind: ComposerAttachment.Kind?, imageSource: CGImageSource?
  ) async throws -> ComposerAttachment {
    let type =
      declaredType(mimeType: mimeType, typeIdentifier: typeIdentifier)
      ?? imageSource.flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) }
    let proposedName =
      filename
      ?? "Attachment \(SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined())"
      + (type?.preferredFilenameExtension.map { "." + $0 } ?? "")
    let basename = try sanitizedFilename(proposedName)
    let directory = temporaryDirectoryURL().appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(basename)
    do {
      try data.write(to: url, options: .atomic)
      return try await inspectFile(
        at: url, storageOwnership: .appOwnedTemporaryFile,
        mimeType: mimeType, typeIdentifier: typeIdentifier, kind: kind,
        data: data, imageSource: imageSource)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  /// Used inside provider callbacks: copy the original bytes while the source URL is valid.
  static func copyToTemporaryStorage(from inputURL: URL, filename: String? = nil) throws -> URL {
    let source = try readableRegularFile(at: inputURL).url
    let basename = try sanitizedFilename(filename ?? inputURL.lastPathComponent)
    let directory = temporaryDirectoryURL().appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let copy = directory.appendingPathComponent(basename)
    do {
      try FileManager.default.copyItem(at: source, to: copy)
      return copy
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  /// Both byte inputs and provider files use the same inspection, identity, and cleanup path.
  static func importOwnedFile(
    at url: URL, mimeType: String? = nil, typeIdentifier: String? = nil,
    kind: ComposerAttachment.Kind? = nil
  ) async throws -> ComposerAttachment {
    try await Task.detached(priority: .userInitiated) {
      try requireTemporaryFile(url)
      do {
        return try await inspectFile(
          at: url, storageOwnership: .appOwnedTemporaryFile,
          mimeType: mimeType, typeIdentifier: typeIdentifier, kind: kind)
      } catch {
        try? removeTemporaryFile(at: url)
        throw error
      }
    }.value
  }

  private static func sanitizedFilename(_ filename: String) throws -> String {
    let basename = (filename as NSString).lastPathComponent
    guard !basename.isEmpty, basename != ".", basename != "..", !basename.contains("\0") else {
      throw ImportError.invalidDraftSource(filename)
    }
    return basename
  }

  private static func filenameDigest(_ filename: String) -> SHA256 {
    var digest = SHA256()
    // Retain the filename+bytes identity, including bytes-only identities for legacy clipboard drafts.
    if !filename.hasPrefix("Clipboard Image ") {
      digest.update(data: Data(filename.utf8))
      digest.update(data: Data([0]))
    }
    return digest
  }

  private static func contentDigest(_ data: Data, filename: String) -> String {
    var digest = filenameDigest(filename)
    digest.update(data: data)
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func contentDigest(at url: URL, filename: String) throws -> String {
    var digest = filenameDigest(filename)
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// File import and receiver eligibility use the same resolved-file rules.
  static func readableRegularFile(at inputURL: URL) throws -> (url: URL, values: URLResourceValues)
  {
    guard inputURL.isFileURL else { throw ImportError.notFileURL(inputURL) }
    var url = inputURL.standardizedFileURL.resolvingSymlinksInPath()
    url.removeAllCachedResourceValues()
    guard FileManager.default.isReadableFile(atPath: url.path),
      let values = try? url.resourceValues(forKeys: [
        .isRegularFileKey, .fileSizeKey, .fileResourceIdentifierKey,
      ]),
      values.isRegularFile == true
    else { throw ImportError.notReadableRegularFile(inputURL) }
    return (url, values)
  }

  static func validateSource(_ attachment: ComposerAttachment) throws -> Int64 {
    var url = attachment.sourceURL
    url.removeAllCachedResourceValues()
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard url.isFileURL, values.isRegularFile == true,
      FileManager.default.isReadableFile(atPath: url.path), let size = values.fileSize
    else { throw ImportError.notReadableRegularFile(url) }
    return Int64(size)
  }

  static func cleanupTemporaryAttachment(_ attachment: ComposerAttachment) throws {
    guard attachment.storageOwnership == .appOwnedTemporaryFile else {
      throw ImportError.cleanupRefused(attachment.sourceURL)
    }
    try removeTemporaryFile(at: attachment.sourceURL)
  }

  private static func requireTemporaryFile(_ url: URL) throws {
    guard
      url.standardizedFileURL.path.hasPrefix(temporaryDirectoryURL().standardizedFileURL.path + "/")
    else {
      throw ImportError.cleanupRefused(url)
    }
  }

  private static func removeTemporaryFile(at url: URL) throws {
    try requireTemporaryFile(url)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    let parent = url.deletingLastPathComponent()
    if parent.deletingLastPathComponent().standardizedFileURL
      == temporaryDirectoryURL().standardizedFileURL,
      UUID(uuidString: parent.lastPathComponent) != nil,
      (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true
    {
      try? FileManager.default.removeItem(at: parent)
    }
  }

  private static func temporaryDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(temporaryDirectoryName, isDirectory: true)
  }

  private static var imageSourceOptions: CFDictionary {
    [kCGImageSourceShouldCache: false] as CFDictionary
  }

  private static func declaredType(mimeType: String?, typeIdentifier: String?) -> UTType? {
    mimeType.flatMap { UTType(mimeType: $0) } ?? typeIdentifier.flatMap { UTType($0) }
  }

  private static func shouldInspectImage(
    declaredType: UTType?, kind: ComposerAttachment.Kind?
  ) -> Bool {
    declaredType == nil || declaredType?.conforms(to: .image) == true || kind == .image
  }

  private static func inspectFile(
    at inputURL: URL,
    storageOwnership: ComposerAttachment.StorageOwnership,
    mimeType: String?, typeIdentifier: String?, kind requestedKind: ComposerAttachment.Kind?,
    data: Data? = nil, imageSource capturedSource: CGImageSource? = nil
  ) async throws -> ComposerAttachment {
    let (url, values) = try readableRegularFile(at: inputURL)
    let declared = declaredType(mimeType: mimeType, typeIdentifier: typeIdentifier)
    // Byte inputs have already been inspected; reuse their source even when inspection returned nil.
    let source =
      data != nil
      ? capturedSource
      : (shouldInspectImage(declaredType: declared, kind: requestedKind)
        ? CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) : nil)
    let detected =
      declared?.preferredMIMEType == nil
      ? source.flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) } : nil
    let type = declared ?? detected ?? UTType(filenameExtension: url.pathExtension) ?? .data
    let kind = requestedKind ?? attachmentKind(for: type)
    let identity: ComposerAttachment.DeduplicationIdentity
    if storageOwnership == .appOwnedTemporaryFile {
      let digest: String
      if let data {
        digest = contentDigest(data, filename: inputURL.lastPathComponent)
      } else {
        digest = try contentDigest(at: url, filename: inputURL.lastPathComponent)
      }
      identity = .contentDigest(digest)
    } else {
      identity = deduplicationIdentity(for: url, resourceIdentifier: values.fileResourceIdentifier)
    }
    let metadata = await mediaMetadata(for: url, kind: kind, imageSource: source)

    return ComposerAttachment(
      sourceURL: url,
      filename: inputURL.lastPathComponent,
      contentType: type,
      byteCount: values.fileSize.map(Int64.init),
      kind: kind,
      storageOwnership: storageOwnership,
      deduplicationIdentity: identity,
      pixelWidth: metadata.width,
      pixelHeight: metadata.height,
      duration: metadata.duration,
      preview: metadata.preview,
      mimeType: mimeType ?? declared?.preferredMIMEType ?? detected?.preferredMIMEType
        ?? type.preferredMIMEType ?? "application/octet-stream"
    )
  }

  private static func attachmentKind(for type: UTType) -> ComposerAttachment.Kind {
    if type.conforms(to: .image) { return .image }
    if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
    if type.conforms(to: .audio) { return .audio }
    return .file
  }

  private static func deduplicationIdentity(for url: URL, resourceIdentifier: Any?)
    -> ComposerAttachment.DeduplicationIdentity
  {
    if let resourceIdentifier {
      return .fileSystemResourceIdentifier(String(describing: resourceIdentifier))
    }
    let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
    if canonicalURL.isFileURL { return .canonicalURL(canonicalURL.absoluteString) }
    return .absolutePath(canonicalURL.path)
  }

  private static func mediaMetadata(
    for url: URL, kind: ComposerAttachment.Kind, imageSource: CGImageSource?
  ) async -> (
    width: Int?, height: Int?, duration: TimeInterval?, preview: NSImage?
  ) {
    switch kind {
    case .image:
      return imageMetadata(from: imageSource)
    case .video:
      let asset = AVURLAsset(url: url)
      let duration = try? await asset.load(.duration).seconds
      let tracks = try? await asset.loadTracks(withMediaType: .video)
      let naturalSize: CGSize?
      if let track = tracks?.first {
        naturalSize = try? await track.load(.naturalSize)
      } else {
        naturalSize = nil
      }
      let preview = await videoPreview(for: asset)
      return (
        naturalSize.map { Int($0.width) }, naturalSize.map { Int($0.height) },
        duration?.isFinite == true ? duration : nil, preview
      )
    case .audio:
      let asset = AVURLAsset(url: url)
      let duration = try? await asset.load(.duration).seconds
      return (nil, nil, duration?.isFinite == true ? duration : nil, nil)
    case .file:
      return (nil, nil, nil, nil)
    }
  }

  private static func imageMetadata(from source: CGImageSource?) -> (
    width: Int?, height: Int?, duration: TimeInterval?, preview: NSImage?
  ) {
    guard let source else { return (nil, nil, nil, nil) }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int
    let height = properties?[kCGImagePropertyPixelHeight] as? Int
    let preview =
      (try? source.orientedBitmap(maximumPixelSize: previewMaximumPixelSize))
      .map { NSImage(cgImage: $0, size: .zero) }
    return (width, height, nil, preview)
  }

  private static func videoPreview(for asset: AVAsset) async -> NSImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: previewMaximumPixelSize, height: previewMaximumPixelSize)
    let image = await withCheckedContinuation { continuation in
      generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
        continuation.resume(returning: image)
      }
    }
    guard let image else { return nil }
    return NSImage(cgImage: image, size: .zero)
  }

}

import AVFoundation
import AppKit
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

struct ComposerAttachmentImporter {
  enum ImportError: Error, LocalizedError {
    case notFileURL(URL)
    case notReadableRegularFile(URL)
    case invalidClipboardImage
    case cleanupRefused(URL)

    var errorDescription: String? {
      switch self {
      case .notFileURL(let url): "Attachment URL is not a file URL: \(url)"
      case .notReadableRegularFile(let url):
        "Attachment is not a readable regular file: \(url.path)"
      case .invalidClipboardImage: "Clipboard data does not contain a valid image"
      case .cleanupRefused(let url): "Refusing to remove externally-owned attachment: \(url.path)"
      }
    }
  }

  private static let temporaryDirectoryName = "MactrixComposerAttachments"
  private static let previewMaximumPixelSize = 512

  /// Imports one readable regular file. This method performs file and media work off the main actor.
  static func importFile(
    at url: URL,
    storageOwnership: ComposerAttachment.StorageOwnership = .externalUserFile
  ) async throws -> ComposerAttachment {
    try await Task.detached(priority: .userInitiated) {
      try await importFileSynchronously(at: url, storageOwnership: storageOwnership)
    }.value
  }

  /// Imports every valid URL in the supplied order. Invalid inputs are logged and do not prevent later files importing.
  static func importFiles(at urls: [URL]) async -> [ComposerAttachment] {
    var attachments: [ComposerAttachment] = []
    for url in urls {
      do {
        attachments.append(try await importFile(at: url))
      } catch {
        Logger.composerAttachment.error(
          "Unable to import attachment \(url.path): \(error)"
        )
      }
    }
    return attachments
  }

  /// Materializes valid PNG or TIFF clipboard data in app-owned temporary storage, then follows the normal file importer path.
  static func importClipboardImage(pngData: Data?, tiffData: Data?) async throws
    -> ComposerAttachment
  {
    let materialized = try await Task.detached(priority: .userInitiated) {
      let png: Data
      let digestSource: Data
      if let pngData, let validPNG = try validPNGData(pngData) {
        png = validPNG
        digestSource = pngData
      } else if let tiffData, let convertedPNG = convertTIFFToPNG(tiffData) {
        png = convertedPNG
        digestSource = tiffData
      } else {
        throw ImportError.invalidClipboardImage
      }
      let digest = SHA256.hash(data: digestSource).map { String(format: "%02x", $0) }.joined()

      let directory = temporaryDirectoryURL()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss_SSS"
      let filename = "Clipboard Image \(formatter.string(from: Date())) \(UUID().uuidString).png"
      let url = directory.appendingPathComponent(filename)
      try png.write(to: url)

      return (url: url, digest: digest)
    }.value

    let imported = try await importFile(
      at: materialized.url, storageOwnership: .appOwnedTemporaryFile
    )

    return ComposerAttachment(
      id: imported.id, sourceURL: imported.sourceURL, filename: imported.filename,
      contentType: imported.contentType, byteCount: imported.byteCount,
      kind: imported.kind, storageOwnership: imported.storageOwnership,
      deduplicationIdentity: .contentDigest(materialized.digest), pixelWidth: imported.pixelWidth,
      pixelHeight: imported.pixelHeight, duration: imported.duration, preview: imported.preview
    )
  }

  static func cleanupTemporaryAttachment(_ attachment: ComposerAttachment) throws {
    let temporaryDirectory = temporaryDirectoryURL().standardizedFileURL.path + "/"
    let attachmentPath = attachment.sourceURL.standardizedFileURL.path
    guard attachment.storageOwnership == .appOwnedTemporaryFile,
      attachmentPath.hasPrefix(temporaryDirectory)
    else {
      throw ImportError.cleanupRefused(attachment.sourceURL)
    }
    try FileManager.default.removeItem(at: attachment.sourceURL)
  }

  private static func temporaryDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(temporaryDirectoryName, isDirectory: true)
  }

  private static func importFileSynchronously(
    at inputURL: URL,
    storageOwnership: ComposerAttachment.StorageOwnership
  ) async throws -> ComposerAttachment {
    guard inputURL.isFileURL else { throw ImportError.notFileURL(inputURL) }

    let url = inputURL.standardizedFileURL.resolvingSymlinksInPath()
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .fileSizeKey, .fileResourceIdentifierKey,
    ])
    guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path) else {
      throw ImportError.notReadableRegularFile(inputURL)
    }

    let type = UTType(filenameExtension: url.pathExtension) ?? .data
    let kind = attachmentKind(for: type)
    let identity = deduplicationIdentity(
      for: url, resourceIdentifier: values.fileResourceIdentifier)
    let metadata = await mediaMetadata(for: url, kind: kind)

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
      preview: metadata.preview
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

  private static func mediaMetadata(for url: URL, kind: ComposerAttachment.Kind) async -> (
    width: Int?, height: Int?, duration: TimeInterval?, preview: NSImage?
  ) {
    switch kind {
    case .image:
      return imageMetadata(for: url)
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

  private static func imageMetadata(for url: URL) -> (
    width: Int?, height: Int?, duration: TimeInterval?, preview: NSImage?
  ) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return (nil, nil, nil, nil)
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int
    let height = properties?[kCGImagePropertyPixelHeight] as? Int
    return (width, height, nil, imagePreview(from: source))
  }

  private static func imagePreview(from source: CGImageSource) -> NSImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: previewMaximumPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return NSImage(cgImage: image, size: .zero)
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

  private static func validPNGData(_ data: Data) throws -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source), UTType(type as String) == .png
    else { return nil }
    return data
  }

  private static func convertTIFFToPNG(_ data: Data) -> Data? {
    guard let image = NSImage(data: data),
      let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff)
    else { return nil }
    return representation.representation(using: .png, properties: [:])
  }
}

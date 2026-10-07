import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension Data {
  func computeMimeType() -> UTType? {
    guard let b: UInt8 = first else { return nil }

    switch b {
    case 0xff:
      return .jpeg
    case 0x89:
      return .png
    case 0x47:
      return .gif
    case 0x4d, 0x49:
      return .tiff
    case 0x25:
      return .pdf
    case 0x46:
      return .plainText
    case 0x52:
      return .webP
    default:
      return nil
    }
  }

  struct ImageDecodeError: Error {}

  /// Decode image data into an NSImage, applying EXIF orientation.
  /// `Image(importing:contentType:)` on macOS does not apply EXIF orientation,
  /// so we route through CIImage which handles it correctly.
  @MainActor
  func toOrientedImage(contentType: UTType? = nil) async throws -> NSImage {
    let task = Task.detached(priority: .utility) {
      try Task.checkCancellation()
      return try self.orientedBitmap(contentType: contentType)
    }
    let bitmap = try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
    try Task.checkCancellation()
    return NSImage(cgImage: bitmap, size: .zero)
  }

  nonisolated func orientedBitmap(contentType: UTType? = nil) throws -> CGImage {
    var sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    if let contentType {
      sourceOptions[kCGImageSourceTypeIdentifierHint] = contentType.identifier
    }
    guard let source = CGImageSourceCreateWithData(self as CFData, sourceOptions as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { throw ImageDecodeError() }

    // At the original pixel dimensions this applies EXIF rotation/mirroring
    // without reducing resolution. ImageIO performs the decode eagerly.
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Swift.max(width, height),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: oriented.width, height: oriented.height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    else { throw ImageDecodeError() }

    // Materialize a standard display bitmap here, including color conversion,
    // instead of retaining a lazy Core Image representation.
    try Task.checkCancellation()
    context.draw(oriented, in: CGRect(x: 0, y: 0, width: oriented.width, height: oriented.height))
    guard let bitmap = context.makeImage() else { throw ImageDecodeError() }
    return bitmap
  }
}

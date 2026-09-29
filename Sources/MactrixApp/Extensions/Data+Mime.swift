import CoreImage
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

    /// Decode image data into an NSImage, applying EXIF orientation.
    /// `Image(importing:contentType:)` on macOS does not apply EXIF orientation,
    /// so we route through CIImage which handles it correctly.
    struct ImageDecodeError: Error {}

    func toOrientedImage(contentType: UTType? = nil) throws -> NSImage {
        guard
            let source = CGImageSourceCreateWithData(self as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageDecodeError()
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let rawOrientation = props?[kCGImagePropertyOrientation as String] as? UInt32
            ?? CGImagePropertyOrientation.up.rawValue
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

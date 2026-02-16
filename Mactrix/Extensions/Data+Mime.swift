import Foundation
import UniformTypeIdentifiers

extension Data {
    func computeMimeType() -> UTType? {
        guard !self.isEmpty else { return nil }
        var b: UInt8 = 0
        self.copyBytes(to: &b, count: 1)

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
}

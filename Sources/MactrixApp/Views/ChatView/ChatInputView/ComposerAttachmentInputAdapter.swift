import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Selects supported representations; the importer validates and stores their bytes.
@MainActor
enum ComposerAttachmentInputAdapter {
  static var dragTypes: [NSPasteboard.PasteboardType] {
    ([UTType.fileURL.identifier, UTType.pdf.identifier]
      + (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []))
      .map { NSPasteboard.PasteboardType($0) }
  }

  static func attachmentOperation(
    from pasteboard: NSPasteboard, sourceOperations: NSDragOperation, enabled: Bool
  ) -> NSDragOperation {
    enabled && sourceOperations.contains(.copy) && canImportAttachments(from: pasteboard)
      ? .copy : []
  }

  private static func rawTypes(_ identifiers: [String]) -> [UTType] {
    let types = identifiers.compactMap(ComposerAttachmentImporter.supportedRawType)
    return types.filter { $0 == .pdf } + types.filter { $0 == .png }
      + types.filter { $0 != .pdf && $0 != .png && $0 != .tiff }
      + types.filter { $0 == .tiff }
  }

  private static func containsText(_ identifiers: [String]) -> Bool {
    identifiers.contains { UTType($0)?.conforms(to: .text) == true }
  }

  private static func canImport(_ identifiers: [String]) -> Bool {
    if identifiers.contains(UTType.fileURL.identifier) { return true }
    return !containsText(identifiers) && !rawTypes(identifiers).isEmpty
  }

  /// Validation uses advertised types only: no data requests, decoding, or file access.
  static func canImportAttachments(from pasteboard: NSPasteboard) -> Bool {
    canImport(advertisedTypes(from: pasteboard))
  }

  private static func advertisedTypes(from pasteboard: NSPasteboard) -> [String] {
    (pasteboard.types ?? []).map(\.rawValue)
      + (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
  }

  /// Capture supported bytes before another copy can replace the pasteboard.
  static func inputs(from pasteboard: NSPasteboard, captureFiles: Bool = false)
    -> [ComposerAttachmentImporter.Input]
  {
    let identifiers = advertisedTypes(from: pasteboard)
    if identifiers.contains(UTType.fileURL.identifier) {
      let urls =
        pasteboard.readObjects(
          forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
      return urls.compactMap { url in
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if captureFiles {
          // Drag access may end as soon as performDragOperation returns.
          return (try? ComposerAttachmentImporter.copyToTemporaryStorage(from: url))
            .map { .ownedFile($0) }
        }
        guard (try? ComposerAttachmentImporter.readableRegularFile(at: url)) != nil else {
          return nil
        }
        return .file(url)
      }
    }
    guard !containsText(identifiers) else { return [] }
    let items = pasteboard.pasteboardItems ?? []
    let inputs = items.compactMap { item in
      rawInput(types: item.types, data: item.data(forType:))
    }
    guard inputs.isEmpty, items.count <= 1 else { return inputs }
    return rawInput(types: pasteboard.types ?? [], data: pasteboard.data(forType:)).map { [$0] }
      ?? []
  }

  private static func rawInput(
    types: [NSPasteboard.PasteboardType], data: (NSPasteboard.PasteboardType) -> Data?
  ) -> ComposerAttachmentImporter.Input? {
    let representations = rawTypes(types.map(\.rawValue)).compactMap { type in
      data(NSPasteboard.PasteboardType(type.identifier)).map {
        ComposerAttachmentImporter.RawRepresentation(data: $0, type: type)
      }
    }
    return representations.isEmpty ? nil : .rawRepresentations(representations)
  }

}

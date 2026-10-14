import AppKit
import OSLog
import UniformTypeIdentifiers

/// Selects supported representations; the importer validates and stores their bytes.
@MainActor
enum ComposerAttachmentInputAdapter {
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

  enum DropMode {
    case files
    case raw
  }

  static func canImportAttachments(from providers: [NSItemProvider], mode: DropMode) -> Bool {
    switch mode {
    case .files: return providers.contains { $0.canLoadObject(ofClass: NSURL.self) }
    case .raw:
      let identifiers = providers.flatMap(\.registeredTypeIdentifiers)
      return !containsText(identifiers) && !rawTypes(identifiers).isEmpty
    }
  }

  private static func advertisedTypes(from pasteboard: NSPasteboard) -> [String] {
    (pasteboard.types ?? []).map(\.rawValue)
      + (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
  }

  /// Capture supported bytes before another copy can replace the pasteboard.
  static func inputs(from pasteboard: NSPasteboard) -> [ComposerAttachmentImporter.Input] {
    let identifiers = advertisedTypes(from: pasteboard)
    if identifiers.contains(UTType.fileURL.identifier) {
      let urls =
        pasteboard.readObjects(
          forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
      return urls.compactMap { url in
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

  /// Must be called inside the drop callback: every provider request starts before this returns.
  @discardableResult
  static func startImportProviders(
    _ providers: [NSItemProvider], mode: DropMode,
    completion: @escaping @MainActor ([ComposerAttachment]) -> Void
  ) -> Bool {
    guard canImportAttachments(from: providers, mode: mode) else { return false }
    let captures: [[AsyncStream<ComposerAttachmentImporter.Input>]] = providers.compactMap {
      provider in
      Logger.composerAttachment.debug(
        "Drop advertised types: \(provider.registeredTypeIdentifiers, privacy: .public)")
      switch mode {
      case .files:
        guard provider.canLoadObject(ofClass: NSURL.self) else { return nil }
        return [captureFile(from: provider)]
      case .raw:
        let captures = rawTypes(provider.registeredTypeIdentifiers).map { type in
          captureData(from: provider, type: type)
        }
        return captures.isEmpty ? nil : captures
      }
    }
    Task {
      var attachments: [ComposerAttachment] = []
      for candidates in captures {
        for candidate in candidates {
          var imported = false
          for await input in candidate {
            do {
              attachments.append(try await ComposerAttachmentImporter.importInput(input))
              imported = true
            } catch {
              Logger.composerAttachment.debug("Unable to import dropped attachment: \(error)")
            }
          }
          if imported { break }
        }
      }
      completion(attachments)
    }
    return true
  }

  private static func captureFile(from provider: NSItemProvider)
    -> AsyncStream<ComposerAttachmentImporter.Input>
  {
    AsyncStream { continuation in
      _ = provider.loadObject(ofClass: NSURL.self) { object, error in
        defer { continuation.finish() }
        guard let url = object as? URL, url.isFileURL else {
          Logger.composerAttachment.debug(
            "Unable to load dropped file URL: \(String(describing: error))")
          return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
          // Copy before returning: access to the provider's URL may end with this callback.
          let copy = try ComposerAttachmentImporter.copyToTemporaryStorage(from: url)
          continuation.yield(.ownedFile(copy))
        } catch {
          Logger.composerAttachment.debug("Unable to capture dropped file: \(error)")
        }
      }
    }
  }

  private static func captureData(from provider: NSItemProvider, type: UTType)
    -> AsyncStream<ComposerAttachmentImporter.Input>
  {
    let filename = provider.suggestedName
    return AsyncStream { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
        defer { continuation.finish() }
        guard let data else {
          Logger.composerAttachment.debug(
            "Unable to load dropped \(type.identifier, privacy: .public): \(String(describing: error))"
          )
          return
        }
        continuation.yield(.rawRepresentations([.init(data: data, type: type, filename: filename)]))
      }
    }
  }
}

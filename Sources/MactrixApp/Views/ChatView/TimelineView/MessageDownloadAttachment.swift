import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog
import UniformTypeIdentifiers

struct MessageDownloadAttachment {
  let source: MediaSource
  let filename: String
  let mimeType: String

  var suggestedFilename: String {
    let name = (filename as NSString).lastPathComponent
    let safeName = name.isEmpty || name == "." || name == ".." ? "Attachment" : name
    if (safeName as NSString).pathExtension.isEmpty,
      let fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
    {
      return "\(safeName).\(fileExtension)"
    }
    return safeName
  }

  static func attachments(for event: EventTimelineItem) -> [Self] {
    guard case .msgLike(let content) = event.content else { return [] }
    switch content.kind {
    case .message(let message):
      switch message.msgType {
      case .image(let image): return [Self(image)]
      case .video(let video): return [Self(video)]
      case .audio(let audio): return [Self(audio)]
      case .file(let file): return [Self(file)]
      case .gallery(let gallery):
        return gallery.itemtypes.compactMap { item in
          switch item {
          case .image(let image): return Self(image)
          case .video(let video): return Self(video)
          case .audio(let audio): return Self(audio)
          case .file(let file): return Self(file)
          case .other: return nil
          }
        }
      default: return []
      }
    case .sticker(let body, let info, let source):
      return [Self(source: source, filename: body, mimeType: info.mimetype ?? "")]
    default: return []
    }
  }

  private init(source: MediaSource, filename: String, mimeType: String) {
    self.source = source
    self.filename = filename
    self.mimeType = mimeType
  }

  private init(_ image: ImageMessageContent) {
    self.init(source: image.source, filename: image.filename, mimeType: image.info?.mimetype ?? "")
  }

  private init(_ video: VideoMessageContent) {
    self.init(source: video.source, filename: video.filename, mimeType: video.info?.mimetype ?? "")
  }

  private init(_ audio: AudioMessageContent) {
    self.init(source: audio.source, filename: audio.filename, mimeType: audio.info?.mimetype ?? "")
  }

  private init(_ file: FileMessageContent) {
    self.init(source: file.source, filename: file.filename, mimeType: file.info?.mimetype ?? "")
  }

  @MainActor
  static func downloadToFile(
    view: NSView, matrixClient: MatrixClient, attachment: MessageDownloadAttachment
  ) async {
    guard let window = view.window else { return }
    let panel = NSSavePanel()
    panel.title = "Download Attachment"
    panel.nameFieldStringValue = attachment.suggestedFilename
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    // startActionTask {
    guard await panel.beginSheetModal(for: window) == .OK,
      let destination = panel.url, !Task.isCancelled
    else { return }
    let scopedAccess = destination.startAccessingSecurityScopedResource()
    defer {
      if scopedAccess { destination.stopAccessingSecurityScopedResource() }
    }
    do {
      let handle = try await matrixClient.client.getMediaFile(
        mediaSource: attachment.source, filename: attachment.suggestedFilename,
        mimeType: attachment.mimeType, useCache: true, tempDir: NSTemporaryDirectory())
      try Task.checkCancellation()
      let writeTask = Task.detached {
        try withExtendedLifetime(handle) {
          try Task.checkCancellation()
          let data = try Data(
            contentsOf: URL(filePath: handle.path()), options: .mappedIfSafe)
          try Task.checkCancellation()
          try data.write(to: destination, options: .atomic)
        }
      }
      try await withTaskCancellationHandler {
        try await writeTask.value
      } onCancel: {
        writeTask.cancel()
      }
    } catch {
      guard !Task.isCancelled else { return }
      Logger.timelineTableView.error("Failed to download attachment: \(error)")
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Could not save attachment"
      alert.informativeText = error.localizedDescription
      await alert.beginSheetModal(for: window)
    }
    // }
  }
}

import AppKit
import MatrixIntegration
import MatrixRustSDK

/// Attachment dispatch shared by gallery display and measurement.
@MainActor
final class MessageAttachmentContent {
  enum Kind: Hashable {
    case image, video, file, unsupported

    init(item: GalleryItemType) {
      switch item {
      case .image: self = .image
      case .video: self = .video
      case .file, .audio: self = .file
      case .other: self = .unsupported
      }
    }
  }

  let kind: Kind
  let view: any MessageContentRowView

  init(item: GalleryItemType) {
    kind = Kind(item: item)
    switch kind {
    case .image: view = MessageImageContentView()
    case .video: view = MessageVideoContentView()
    case .file: view = MessageFileContentView()
    case .unsupported: view = MessageTextContentView()
    }
  }

  func configure(item: GalleryItemType, matrixClient: MatrixClient?) {
    switch item {
    case .image(let image):
      (view as? MessageImageContentView)?.configure(image: image, matrixClient: matrixClient)
    case .video(let video):
      (view as? MessageVideoContentView)?.configure(video: video, matrixClient: matrixClient)
    case .file(let file):
      (view as? MessageFileContentView)?.configure(file: file, matrixClient: matrixClient)
    case .audio(let audio):
      (view as? MessageFileContentView)?.configure(
        file: Self.fileFallback(for: audio), matrixClient: matrixClient)
    case .other(let itemtype, let body):
      (view as? MessageTextContentView)?.configureCaption(
        "Unsupported attachment (\(itemtype)): \(body)", formatted: nil)
    }
  }

  func height(for item: GalleryItemType, width: CGFloat) -> CGFloat {
    switch item {
    case .image(let image):
      return (view as? MessageImageContentView)?.height(for: image, width: width) ?? 0
    case .video(let video):
      return (view as? MessageVideoContentView)?.height(for: video, width: width) ?? 0
    case .file(let file):
      return (view as? MessageFileContentView)?.height(for: file, width: width) ?? 0
    case .audio(let audio):
      return (view as? MessageFileContentView)?.height(
        for: Self.fileFallback(for: audio), width: width) ?? 0
    case .other(let itemtype, let body):
      return (view as? MessageTextContentView)?.height(
        forCaption: "Unsupported attachment (\(itemtype)): \(body)", formatted: nil, width: width)
        ?? 0
    }
  }

  func prepareForReuse() {
    (view as? MessageImageContentView)?.resetMedia()
    (view as? MessageVideoContentView)?.resetMedia()
    (view as? MessageFileContentView)?.resetMedia()
    view.onSelectRequest = nil
    view.onArrowKey = nil
    if let preview = view as? any MessageMediaPreviewContentView {
      preview.onMediaPreviewRequest = nil
      preview.onMediaPreview = nil
    }
  }

  // Until an audio player is available, preserve its source and captions in a previewable file view.
  private static func fileFallback(for audio: AudioMessageContent) -> FileMessageContent {
    FileMessageContent(
      filename: audio.filename, caption: audio.caption, formattedCaption: audio.formattedCaption,
      source: audio.source, info: nil)
  }
}

import Foundation
import MatrixRustSDK

struct PreparedMediaUpload {
  enum Media {
    case image(ImageInfo, thumbnailSource: UploadSource?)
    case video(VideoInfo, thumbnailSource: UploadSource?)
    case audio(AudioInfo)
    case file(FileInfo)
  }

  let attachment: ComposerAttachment
  let parameters: UploadParameters
  let media: Media

  var asGalleryItemInfo: GalleryItemInfo {
    switch self.media {
    case .audio(let audio):
      GalleryItemInfo.audio(
        audioInfo: audio,
        source: parameters.source,
        caption: parameters.caption,
        formattedCaption: nil,
      )
    case .file(let file):
      GalleryItemInfo.file(
        fileInfo: file,
        source: parameters.source,
        caption: parameters.caption,
        formattedCaption: nil,
      )
    case .image(let image, let thumbnailSource):
      GalleryItemInfo.image(
        imageInfo: image,
        source: parameters.source,
        caption: parameters.caption,
        formattedCaption: nil,
        thumbnailSource: thumbnailSource,
      )
    case .video(let video, let thumbnailSource):
      GalleryItemInfo.video(
        videoInfo: video,
        source: parameters.source,
        caption: parameters.caption,
        formattedCaption: nil,
        thumbnailSource: thumbnailSource,
      )
    }
  }
}

enum ComposerMediaPreparation {
  /// Re-importing immediately before enqueueing confirms that the path still names a
  /// readable regular file and refreshes its size and media metadata.
  static func prepare(
    attachment: ComposerAttachment, caption: String, replyID: String?
  ) async throws -> PreparedMediaUpload {
    let refreshed = try await ComposerAttachmentImporter.importFile(
      at: attachment.sourceURL, storageOwnership: attachment.storageOwnership)
    let source = UploadSource.file(filename: refreshed.sourceURL.path)
    let parameters = UploadParameters(
      source: source,
      caption: caption.isEmpty ? nil : caption,
      formattedCaption: nil,
      mentions: nil,
      inReplyTo: replyID,
      extraContentJson: nil)
    let size = refreshed.byteCount.flatMap { $0 >= 0 ? UInt64($0) : nil }

    switch refreshed.kind {
    case .image:
      return PreparedMediaUpload(
        attachment: refreshed, parameters: parameters,
        media: .image(
          ImageInfo(
            height: refreshed.pixelHeight.map(UInt64.init),
            width: refreshed.pixelWidth.map(UInt64.init),
            mimetype: refreshed.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil,
            blurhash: nil, isAnimated: nil),
          thumbnailSource: nil))
    case .video:
      return PreparedMediaUpload(
        attachment: refreshed, parameters: parameters,
        media: .video(
          VideoInfo(
            duration: refreshed.duration, height: refreshed.pixelHeight.map(UInt64.init),
            width: refreshed.pixelWidth.map(UInt64.init), mimetype: refreshed.mimeType, size: size,
            thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil),
          thumbnailSource: nil))
    case .audio:
      return PreparedMediaUpload(
        attachment: refreshed, parameters: parameters,
        media: .audio(
          AudioInfo(duration: refreshed.duration, size: size, mimetype: refreshed.mimeType)))
    case .file:
      return PreparedMediaUpload(
        attachment: refreshed, parameters: parameters,
        media: .file(
          FileInfo(
            mimetype: refreshed.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil)))
    }
  }
}

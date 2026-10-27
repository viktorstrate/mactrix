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
  /// Validate the source without discarding the selected representation metadata.
  static func prepare(
    attachment: ComposerAttachment, caption: String, replyID: String?, mentions: Mentions? = nil
  ) async throws -> PreparedMediaUpload {
    let byteCount = try ComposerAttachmentImporter.validateSource(attachment)
    let source = UploadSource.file(filename: attachment.sourceURL.path)
    let parameters = UploadParameters(
      source: source,
      caption: caption.isEmpty ? nil : caption,
      formattedCaption: nil,
      mentions: mentions,
      inReplyTo: replyID,
      extraContentJson: nil)
    let size = UInt64(byteCount)

    switch attachment.kind {
    case .image:
      return PreparedMediaUpload(
        attachment: attachment, parameters: parameters,
        media: .image(
          ImageInfo(
            height: attachment.pixelHeight.map(UInt64.init),
            width: attachment.pixelWidth.map(UInt64.init),
            mimetype: attachment.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil,
            blurhash: nil, isAnimated: nil),
          thumbnailSource: nil))
    case .video:
      return PreparedMediaUpload(
        attachment: attachment, parameters: parameters,
        media: .video(
          VideoInfo(
            duration: attachment.duration, height: attachment.pixelHeight.map(UInt64.init),
            width: attachment.pixelWidth.map(UInt64.init), mimetype: attachment.mimeType,
            size: size,
            thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil),
          thumbnailSource: nil))
    case .audio:
      return PreparedMediaUpload(
        attachment: attachment, parameters: parameters,
        media: .audio(
          AudioInfo(duration: attachment.duration, size: size, mimetype: attachment.mimeType)))
    case .file:
      return PreparedMediaUpload(
        attachment: attachment, parameters: parameters,
        media: .file(
          FileInfo(
            mimetype: attachment.mimeType, size: size, thumbnailInfo: nil, thumbnailSource: nil)))
    }
  }
}

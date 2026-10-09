import AppKit
import MatrixIntegration
import MatrixRustSDK

/// Content retained by a message row across NSTableView reuse.
protocol MessageContentRowView: NSView {
  var onSelectRequest: (() -> Void)? { get set }
  var onArrowKey: ((TimelineSelectionDirection) -> Void)? { get set }
  func configure(content: MatrixRustSDK.MsgLikeContent, matrixClient: MatrixClient?)
  func height(for content: MatrixRustSDK.MsgLikeContent, width: CGFloat) -> CGFloat
  func configureEditing(_ state: MessageEditState?)
}

extension MessageContentRowView {
  func configureEditing(_ state: MessageEditState?) {}
}

/// Media rows deliver downloaded files to their owning timeline controller.
protocol MessageMediaPreviewContentView: MessageContentRowView {
  /// Returns true when an existing preview was closed, avoiding another download.
  var onMediaPreviewRequest: (() -> Bool)? { get set }
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)? { get set }
}

/// Determines the reusable row and its retained content view for a message.
@MainActor enum MessageContentKind: Hashable {
  case text
  case image
  case video
  case file
  case gallery

  init(content: MatrixRustSDK.MsgLikeContent) {
    if case .message(let message) = content.kind, case .gallery = message.msgType {
      self = .gallery
    } else if MessageImageContentView.supports(content: content) {
      self = .image
    } else if MessageVideoContentView.supports(content: content) {
      self = .video
    } else if MessageFileContentView.supports(content: content) {
      self = .file
    } else {
      self = .text
    }
  }

  var reuseIdentifier: NSUserInterfaceItemIdentifier {
    switch self {
    case .text: .init("message.text")
    case .image: .init("message.image")
    case .video: .init("message.video")
    case .file: .init("message.file")
    case .gallery: .init("message.gallery")
    }
  }

  func makeRowView() -> MessageRowView {
    let contentView: any MessageContentRowView
    switch self {
    case .text: contentView = MessageTextContentView()
    case .image: contentView = MessageImageContentView()
    case .video: contentView = MessageVideoContentView()
    case .file: contentView = MessageFileContentView()
    case .gallery: contentView = MessageGalleryContentView()
    }
    return MessageRowView(contentKind: self, contentView: contentView)
  }
}

import AppKit
import MatrixIntegration
import MatrixRustSDK

/// One event's ordered attachments and final caption, retained within a single timeline row.
final class MessageGalleryContentView: NSView, MessageMediaPreviewContentView {
  var onSelectRequest: (() -> Void)? { didSet { updateCallbacks() } }
  var onArrowKey: ((TimelineSelectionDirection) -> Void)? { didSet { updateCallbacks() } }
  var onMediaPreviewRequest: (() -> Bool)? { didSet { updateCallbacks() } }
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)? { didSet { updateCallbacks() } }

  private static let itemSpacing: CGFloat = 16
  private static let captionSpacing: CGFloat = 10
  private let captionView = MessageTextContentView()
  private let captionMeasurementView = MessageTextContentView()
  private var attachments: [MessageAttachmentContent] = []
  private var measurementViews: [MessageAttachmentContent.Kind: MessageAttachmentContent] = [:]
  private var gallery: GalleryMessageContent?
  private var compositionConstraints: [NSLayoutConstraint] = []
  private var attachmentHeightConstraints: [NSLayoutConstraint] = []
  private var captionHeightConstraint: NSLayoutConstraint?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    captionView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(captionView)
  }

  func configure(content: MsgLikeContent, matrixClient: MatrixClient?) {
    guard case .message(let message) = content.kind,
      case .gallery(let gallery) = message.msgType
    else { return }
    configure(gallery: gallery, matrixClient: matrixClient)
  }

  func configure(gallery: GalleryMessageContent, matrixClient: MatrixClient?) {
    self.gallery = gallery
    NSLayoutConstraint.deactivate(compositionConstraints)
    compositionConstraints = []
    attachmentHeightConstraints = []
    captionHeightConstraint = nil

    var nextAttachments: [MessageAttachmentContent] = []
    for (index, item) in gallery.itemtypes.enumerated() {
      let attachment: MessageAttachmentContent
      if index < attachments.count, attachments[index].kind == .init(item: item) {
        attachment = attachments[index]
      } else {
        if index < attachments.count {
          attachments[index].prepareForReuse()
          attachments[index].view.removeFromSuperview()
        }
        attachment = MessageAttachmentContent(item: item)
        attachment.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attachment.view)
      }
      attachment.configure(item: item, matrixClient: matrixClient)
      nextAttachments.append(attachment)
    }
    for attachment in attachments.dropFirst(gallery.itemtypes.count) {
      attachment.prepareForReuse()
      attachment.view.removeFromSuperview()
    }
    attachments = nextAttachments

    var previous: NSView?
    for attachment in attachments {
      let view = attachment.view
      let height = view.heightAnchor.constraint(equalToConstant: 0)
      attachmentHeightConstraints.append(height)
      compositionConstraints += [
        view.leadingAnchor.constraint(equalTo: leadingAnchor),
        view.trailingAnchor.constraint(equalTo: trailingAnchor),
        view.topAnchor.constraint(
          equalTo: previous?.bottomAnchor ?? topAnchor,
          constant: previous == nil ? 0 : Self.itemSpacing),
        height,
      ]
      previous = view
    }

    let hasCaption = Self.hasCaption(gallery)
    captionView.isHidden = !hasCaption
    captionView.configureCaption(gallery.body, formatted: gallery.formatted)
    if hasCaption {
      let height = captionView.heightAnchor.constraint(equalToConstant: 0)
      captionHeightConstraint = height
      compositionConstraints += [
        captionView.leadingAnchor.constraint(equalTo: leadingAnchor),
        captionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        captionView.topAnchor.constraint(
          equalTo: previous?.bottomAnchor ?? topAnchor,
          constant: previous == nil ? 0 : Self.captionSpacing),
        height,
      ]
      previous = captionView
    }
    let bottom =
      previous?.bottomAnchor.constraint(equalTo: bottomAnchor)
      ?? heightAnchor.constraint(equalToConstant: 0)
    bottom.priority = .init(999)
    compositionConstraints.append(bottom)
    updateHeights()
    NSLayoutConstraint.activate(compositionConstraints)
    updateCallbacks()
  }

  override func layout() {
    updateHeights()
    super.layout()
  }

  func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
    guard case .message(let message) = content.kind,
      case .gallery(let gallery) = message.msgType
    else { return 0 }
    return height(for: gallery, width: width)
  }

  func height(for gallery: GalleryMessageContent, width: CGFloat) -> CGFloat {
    let width = max(width, 1)
    let itemHeights = gallery.itemtypes.map { measure(item: $0, width: width) }
    var height =
      itemHeights.reduce(0, +)
      + CGFloat(max(itemHeights.count - 1, 0)) * Self.itemSpacing
    if Self.hasCaption(gallery) {
      height +=
        (itemHeights.isEmpty ? 0 : Self.captionSpacing)
        + ceil(
          captionMeasurementView.height(
            forCaption: gallery.body, formatted: gallery.formatted, width: width))
    }
    return height
  }

  private func measure(item: GalleryItemType, width: CGFloat) -> CGFloat {
    let kind = MessageAttachmentContent.Kind(item: item)
    let measurement = measurementViews[kind] ?? MessageAttachmentContent(item: item)
    measurementViews[kind] = measurement
    // Measurement never configures media and therefore cannot start a download or playback.
    return ceil(measurement.height(for: item, width: width))
  }

  private func updateHeights() {
    guard let gallery else { return }
    let width = max(bounds.width, 1)
    for (item, constraint) in zip(gallery.itemtypes, attachmentHeightConstraints) {
      let height = measure(item: item, width: width)
      if constraint.constant != height { constraint.constant = height }
    }
    if let captionHeightConstraint {
      let height = ceil(
        captionMeasurementView.height(
          forCaption: gallery.body, formatted: gallery.formatted, width: width))
      if captionHeightConstraint.constant != height { captionHeightConstraint.constant = height }
    }
  }

  private func updateCallbacks() {
    captionView.onSelectRequest = onSelectRequest
    captionView.onArrowKey = onArrowKey
    for attachment in attachments {
      attachment.view.onSelectRequest = onSelectRequest
      attachment.view.onArrowKey = onArrowKey
      if let preview = attachment.view as? any MessageMediaPreviewContentView {
        preview.onMediaPreviewRequest = onMediaPreviewRequest
        preview.onMediaPreview = onMediaPreview
      }
    }
  }

  private static func hasCaption(_ gallery: GalleryMessageContent) -> Bool {
    !gallery.body.isEmpty || gallery.formatted != nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog

/// One image and its optional text caption. Both views survive table row reuse.
final class MessageImageContentView: NSView, MessageMediaPreviewContentView {
  var onMediaPreviewRequest: (() -> Bool)?
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)?
  var onSelectRequest: (() -> Void)? {
    didSet { captionView.onSelectRequest = onSelectRequest }
  }
  var onArrowKey: ((TimelineSelectionDirection) -> Void)? {
    didSet { captionView.onArrowKey = onArrowKey }
  }

  private let imageButton = NSButton()
  private let spinner = NSProgressIndicator()
  private let errorLabel = NSTextField(labelWithString: "")
  private let captionView = MessageTextContentView()
  private var imageWidthConstraint: NSLayoutConstraint!
  private var imageHeightConstraint: NSLayoutConstraint!
  private var imageBottomConstraint: NSLayoutConstraint!
  private var captionBottomConstraint: NSLayoutConstraint!
  private var sourceURL: String?
  private var imageContent: ImageMessageContent?
  private weak var matrixClient: MatrixClient?
  private var loadTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    imageButton.isBordered = false
    imageButton.imagePosition = .imageOnly
    imageButton.imageScaling = .scaleProportionallyDown
    imageButton.target = self
    imageButton.action = #selector(previewImage)
    imageButton.wantsLayer = true
    imageButton.layer?.cornerRadius = 6
    imageButton.layer?.masksToBounds = true

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    errorLabel.textColor = .systemRed
    errorLabel.alignment = .center
    errorLabel.isSelectable = true
    errorLabel.usesSingleLineMode = false
    errorLabel.lineBreakMode = .byWordWrapping
    errorLabel.maximumNumberOfLines = 0
    errorLabel.isHidden = true

    for view in [imageButton, spinner, errorLabel, captionView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }

    imageWidthConstraint = imageButton.widthAnchor.constraint(equalToConstant: 300)
    imageHeightConstraint = imageButton.heightAnchor.constraint(equalToConstant: 300)
    imageBottomConstraint = imageButton.bottomAnchor.constraint(equalTo: bottomAnchor)
    captionBottomConstraint = captionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    imageBottomConstraint.priority = .init(999)
    captionBottomConstraint.priority = .init(999)
    NSLayoutConstraint.activate([
      imageButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageButton.topAnchor.constraint(equalTo: topAnchor),
      imageWidthConstraint,
      imageHeightConstraint,
      spinner.centerXAnchor.constraint(equalTo: imageButton.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: imageButton.centerYAnchor),
      errorLabel.leadingAnchor.constraint(equalTo: imageButton.leadingAnchor),
      errorLabel.trailingAnchor.constraint(equalTo: imageButton.trailingAnchor),
      errorLabel.centerYAnchor.constraint(equalTo: imageButton.centerYAnchor),
      captionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      captionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      captionView.topAnchor.constraint(equalTo: imageButton.bottomAnchor, constant: 10),
    ])
  }

  static func supports(content: MsgLikeContent) -> Bool {
    guard case .message(let message) = content.kind else { return false }
    if case .image = message.msgType { return true }
    return false
  }

  func configure(content: MsgLikeContent, matrixClient: MatrixClient?) {
    guard case .message(let message) = content.kind,
      case .image(let image) = message.msgType
    else { return }

    configure(image: image, matrixClient: matrixClient)
  }

  func configure(image: ImageMessageContent, matrixClient: MatrixClient?) {
    self.imageContent = image
    self.matrixClient = matrixClient
    let hasCaption = image.caption?.isEmpty == false || image.formattedCaption != nil
    captionView.isHidden = !hasCaption
    captionView.configureCaption(image.caption, formatted: image.formattedCaption)
    imageBottomConstraint.isActive = !hasCaption
    captionBottomConstraint.isActive = hasCaption
    updateImageSize(for: image, width: bounds.width)

    let url = image.source.url()
    guard url != sourceURL else { return }
    loadTask?.cancel()
    previewTask?.cancel()
    loadTask = nil
    previewTask = nil
    sourceURL = url
    errorLabel.isHidden = true
    imageButton.toolTip = image.filename
    imageButton.image = MatrixClient.imageCache.object(forKey: NSString(string: url))
    imageButton.isEnabled = imageButton.image != nil
    if imageButton.image == nil {
      spinner.startAnimation(nil)
      loadImage(image, from: matrixClient)
    } else {
      spinner.stopAnimation(nil)
    }
  }

  override func layout() {
    super.layout()
    guard let imageContent else { return }
    updateImageSize(for: imageContent, width: bounds.width)
  }

  func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
    guard case .message(let message) = content.kind,
      case .image(let image) = message.msgType
    else { return 0 }
    return height(for: image, width: width)
  }

  func height(for image: ImageMessageContent, width: CGFloat) -> CGFloat {
    let imageHeight = Self.imageSize(for: image, width: width).height
    guard image.caption?.isEmpty == false || image.formattedCaption != nil else {
      return imageHeight
    }
    return imageHeight + 10
      + ceil(
        captionView.height(
          forCaption: image.caption, formatted: image.formattedCaption, width: width))
  }

  private func updateImageSize(for image: ImageMessageContent, width: CGFloat) {
    let size = Self.imageSize(for: image, width: max(width, 1))
    imageWidthConstraint.constant = size.width
    imageHeightConstraint.constant = size.height
  }

  private static func imageSize(for image: ImageMessageContent, width: CGFloat) -> CGSize {
    guard let info = image.info, let pixelWidth = info.width, let pixelHeight = info.height,
      pixelWidth > 0, pixelHeight > 0
    else {
      let side = min(width, 300)
      return CGSize(width: side, height: side)
    }
    let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
    let imageWidth = min(width, CGFloat(pixelWidth), 300 * ratio)
    return CGSize(width: imageWidth, height: imageWidth / ratio)
  }

  private func loadImage(_ image: ImageMessageContent, from client: MatrixClient?) {
    guard let client else {
      showError("Matrix client not available")
      return
    }
    let url = image.source.url()
    loadTask = Task { [weak self] in
      do {
        let data = try await client.client.getMediaContent(mediaSource: image.source)
        try Task.checkCancellation()
        let cacheKey = NSString(string: url)
        let decoded =
          try MatrixClient.imageCache.object(forKey: cacheKey)
          ?? data.toOrientedImage(contentType: data.computeMimeType())
        try Task.checkCancellation()
        MatrixClient.setCachedImage(decoded, forKey: cacheKey)
        guard let self, self.sourceURL == url else { return }
        self.imageButton.image = decoded
        self.imageButton.isEnabled = true
        self.spinner.stopAnimation(nil)
        self.loadTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.sourceURL == url else { return }
        self.showError(error.localizedDescription)
        self.loadTask = nil
      }
    }
  }

  private func showError(_ message: String) {
    spinner.stopAnimation(nil)
    errorLabel.stringValue = message
    errorLabel.isHidden = false
  }

  @objc private func previewImage() {
    guard let imageContent, let window else { return }
    if onMediaPreviewRequest?() == true { return }
    guard let matrixClient else { return }
    let url = imageContent.source.url()
    previewTask?.cancel()
    previewTask = Task { [weak self, weak window] in
      do {
        let handle = try await matrixClient.client.getMediaFile(
          mediaSource: imageContent.source,
          filename: imageContent.filename,
          mimeType: imageContent.info?.mimetype ?? "",
          useCache: true,
          tempDir: NSTemporaryDirectory()
        )
        try Task.checkCancellation()
        let path = try handle.path()
        guard let self, let window, self.window === window, self.sourceURL == url else {
          return
        }
        self.onMediaPreview?(
          URL(filePath: path, directoryHint: .notDirectory), handle)
        self.previewTask = nil
      } catch is CancellationError {
        return
      } catch {
        Logger.viewCycle.error("failed to preview image: \(error)")
      }
    }
  }

  func resetMedia() {
    loadTask?.cancel()
    previewTask?.cancel()
    loadTask = nil
    previewTask = nil
    sourceURL = nil
    imageContent = nil
    matrixClient = nil
    imageButton.image = nil
    spinner.stopAnimation(nil)
  }

  deinit {
    loadTask?.cancel()
    previewTask?.cancel()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

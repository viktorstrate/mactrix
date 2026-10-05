import AVKit
import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog

/// A retained video player, thumbnail, and optional caption for a reusable message row.
final class MessageVideoContentView: NSView, MessageContentRowView {
  var onSelectRequest: (() -> Void)? {
    didSet { captionView.onSelectRequest = onSelectRequest }
  }

  var onArrowKey: ((TimelineSelectionDirection) -> Void)? {
    didSet { captionView.onArrowKey = onArrowKey }
  }

  private let mediaView = NSView()
  private let thumbnailView = NSImageView()
  private let playButton = NSButton()
  private var playerView: AVPlayerView?
  private let spinner = NSProgressIndicator()
  private let errorLabel = NSTextField(labelWithString: "")
  private let captionView = MessageTextContentView()
  private var mediaWidthConstraint: NSLayoutConstraint!
  private var mediaHeightConstraint: NSLayoutConstraint!
  private var mediaBottomConstraint: NSLayoutConstraint!
  private var captionBottomConstraint: NSLayoutConstraint!
  private var videoContent: VideoMessageContent?
  private var sourceURL: String?
  private weak var matrixClient: MatrixClient?
  private var fileHandle: MediaFileHandle?
  private var thumbnailTask: Task<Void, Never>?
  private var videoTask: Task<Void, Never>?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    mediaView.wantsLayer = true
    mediaView.layer?.backgroundColor = NSColor.darkGray.cgColor
    mediaView.layer?.cornerRadius = 6
    mediaView.layer?.masksToBounds = true
    thumbnailView.imageScaling = .scaleProportionallyUpOrDown

    playButton.isBordered = false
    playButton.image = NSImage(
      systemSymbolName: "play.fill", accessibilityDescription: "Play video")?
      .withSymbolConfiguration(.init(pointSize: 32, weight: .regular))
    playButton.contentTintColor = .white
    playButton.target = self
    playButton.action = #selector(playVideo)
    playButton.toolTip = "Play video"

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

    for view in [mediaView, captionView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    for view in [thumbnailView, playButton, spinner, errorLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      mediaView.addSubview(view)
    }

    mediaWidthConstraint = mediaView.widthAnchor.constraint(equalToConstant: 300)
    mediaHeightConstraint = mediaView.heightAnchor.constraint(equalToConstant: 300)
    mediaBottomConstraint = mediaView.bottomAnchor.constraint(equalTo: bottomAnchor)
    captionBottomConstraint = captionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    mediaBottomConstraint.priority = .init(999)
    captionBottomConstraint.priority = .init(999)
    NSLayoutConstraint.activate([
      mediaView.leadingAnchor.constraint(equalTo: leadingAnchor),
      mediaView.topAnchor.constraint(equalTo: topAnchor),
      mediaWidthConstraint,
      mediaHeightConstraint,
      thumbnailView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
      thumbnailView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
      thumbnailView.topAnchor.constraint(equalTo: mediaView.topAnchor),
      thumbnailView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
      playButton.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
      playButton.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
      playButton.topAnchor.constraint(equalTo: mediaView.topAnchor),
      playButton.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
      spinner.centerXAnchor.constraint(equalTo: mediaView.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: mediaView.centerYAnchor),
      errorLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
      errorLabel.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
      errorLabel.centerYAnchor.constraint(equalTo: mediaView.centerYAnchor),
      captionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      captionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      captionView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 10),
    ])
  }

  static func supports(content: MsgLikeContent) -> Bool {
    guard case .message(let message) = content.kind else { return false }
    if case .video = message.msgType {
      return true
    }
    return false
  }

  func configure(content: MsgLikeContent, matrixClient: MatrixClient?) {
    guard case .message(let message) = content.kind,
      case .video(let video) = message.msgType
    else { return }

    configure(video: video, matrixClient: matrixClient)
  }

  func configure(video: VideoMessageContent, matrixClient: MatrixClient?) {
    videoContent = video
    self.matrixClient = matrixClient
    let hasCaption = video.caption?.isEmpty == false || video.formattedCaption != nil
    captionView.isHidden = !hasCaption
    captionView.configureCaption(video.caption, formatted: video.formattedCaption)
    mediaBottomConstraint.isActive = !hasCaption
    captionBottomConstraint.isActive = hasCaption
    if bounds.width > 0 {
      updateMediaSize(for: video, width: bounds.width)
    }

    let url = video.source.url()
    guard sourceURL != url else { return }
    thumbnailTask?.cancel()
    videoTask?.cancel()
    thumbnailTask = nil
    videoTask = nil
    sourceURL = url
    playerView?.player?.pause()
    playerView?.player = nil
    playerView?.isHidden = true
    fileHandle = nil
    spinner.stopAnimation(nil)
    errorLabel.isHidden = true
    playButton.isHidden = false
    playButton.isEnabled = true
    thumbnailView.image = nil
    loadThumbnail(for: video, from: matrixClient)
  }

  override func layout() {
    if let videoContent, bounds.width > 0 {
      updateMediaSize(for: videoContent, width: bounds.width)
    }
    super.layout()
  }

  func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
    guard case .message(let message) = content.kind,
      case .video(let video) = message.msgType
    else { return 0 }
    return height(for: video, width: width)
  }

  func height(for video: VideoMessageContent, width: CGFloat) -> CGFloat {
    let mediaHeight = Self.mediaSize(for: video, width: width).height
    guard video.caption?.isEmpty == false || video.formattedCaption != nil else {
      return mediaHeight
    }
    return mediaHeight + 10
      + ceil(
        captionView.height(
          forCaption: video.caption, formatted: video.formattedCaption, width: width))
  }

  private func updateMediaSize(for video: VideoMessageContent, width: CGFloat) {
    let size = Self.mediaSize(for: video, width: width)
    if mediaWidthConstraint.constant != size.width {
      mediaWidthConstraint.constant = size.width
    }
    if mediaHeightConstraint.constant != size.height {
      mediaHeightConstraint.constant = size.height
    }
  }

  private static func mediaSize(for video: VideoMessageContent, width: CGFloat) -> CGSize {
    guard let info = video.info, let pixelWidth = info.width, let pixelHeight = info.height,
      pixelWidth > 0, pixelHeight > 0
    else {
      let side = min(width, 300)
      return CGSize(width: side, height: side)
    }
    let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
    let mediaWidth = min(width, CGFloat(pixelWidth), 300 * ratio)
    return CGSize(width: mediaWidth, height: mediaWidth / ratio)
  }

  private func loadThumbnail(for video: VideoMessageContent, from client: MatrixClient?) {
    guard let source = video.info?.thumbnailSource, let client else { return }
    let url = video.source.url()
    if let cached = client.cachedImage(matrixUrl: source.url()) {
      thumbnailView.image = cached
      return
    }
    thumbnailTask = Task { [weak self] in
      do {
        let data = try await client.client.getMediaContent(mediaSource: source)
        try Task.checkCancellation()
        let image = try data.toOrientedImage(contentType: data.computeMimeType())
        try Task.checkCancellation()
        MatrixClient.setCachedImage(image, forKey: NSString(string: source.url()))
        guard let self, self.sourceURL == url else { return }
        self.thumbnailView.image = image
        self.thumbnailTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.sourceURL == url else { return }
        Logger.viewCycle.error("Failed to load video thumbnail: \(error)")
        self.thumbnailTask = nil
      }
    }
  }

  @objc private func playVideo() {
    guard let videoContent, let matrixClient else { return }
    let url = videoContent.source.url()
    playButton.isEnabled = false
    spinner.startAnimation(nil)
    videoTask?.cancel()
    videoTask = Task { [weak self] in
      do {
        let handle = try await matrixClient.client.getMediaFile(
          mediaSource: videoContent.source,
          filename: videoContent.filename,
          mimeType: videoContent.info?.mimetype ?? "",
          useCache: true,
          tempDir: NSTemporaryDirectory()
        )
        try Task.checkCancellation()
        let path = try handle.path()
        guard let self, self.sourceURL == url else { return }
        self.fileHandle = handle
        let player = AVPlayer(url: URL(filePath: path, directoryHint: .notDirectory))
        let playerView = self.preparePlayerView()
        playerView.player = player
        playerView.isHidden = false
        self.playButton.isHidden = true
        self.spinner.stopAnimation(nil)
        self.videoTask = nil
        player.play()
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.sourceURL == url else { return }
        self.spinner.stopAnimation(nil)
        self.playButton.isEnabled = true
        self.errorLabel.stringValue = error.localizedDescription
        self.errorLabel.isHidden = false
        self.videoTask = nil
      }
    }
  }

  private func preparePlayerView() -> AVPlayerView {
    if let playerView {
      return playerView
    }

    let view = AVPlayerView(frame: mediaView.bounds)
    view.allowsPictureInPicturePlayback = true
    view.showsFullScreenToggleButton = true
    view.showsSharingServiceButton = true
    view.translatesAutoresizingMaskIntoConstraints = false
    mediaView.addSubview(view, positioned: .above, relativeTo: thumbnailView)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
      view.topAnchor.constraint(equalTo: mediaView.topAnchor),
      view.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
    ])
    playerView = view
    return view
  }

  func resetMedia() {
    thumbnailTask?.cancel()
    videoTask?.cancel()
    thumbnailTask = nil
    videoTask = nil
    playerView?.player?.pause()
    playerView?.player = nil
    playerView?.isHidden = true
    fileHandle = nil
    sourceURL = nil
    videoContent = nil
    matrixClient = nil
    thumbnailView.image = nil
    spinner.stopAnimation(nil)
  }

  @MainActor
  deinit {
    thumbnailTask?.cancel()
    videoTask?.cancel()
    playerView?.player?.pause()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

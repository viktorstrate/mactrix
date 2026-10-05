import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog
import UniformTypeIdentifiers

final class MessageFileContentView: NSView, MessageMediaPreviewContentView {
  var onMediaPreviewRequest: (() -> Bool)?
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)?
  var onSelectRequest: (() -> Void)? {
    didSet { captionView.onSelectRequest = onSelectRequest }
  }

  var onArrowKey: ((TimelineSelectionDirection) -> Void)? {
    didSet { captionView.onArrowKey = onArrowKey }
  }

  private let fileButton = FilePreviewButton()
  private let captionView = MessageTextContentView()
  private var fileBottomConstraint: NSLayoutConstraint!
  private var captionBottomConstraint: NSLayoutConstraint!
  private var fileContent: FileMessageContent?
  private weak var matrixClient: MatrixClient?
  private var sourceURL: String?
  private var previewTask: Task<Void, Never>?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    fileButton.target = self
    fileButton.action = #selector(previewFile)

    for view in [fileButton, captionView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }

    fileBottomConstraint = fileButton.bottomAnchor.constraint(equalTo: bottomAnchor)
    captionBottomConstraint = captionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    fileBottomConstraint.priority = .init(999)
    captionBottomConstraint.priority = .init(999)
    NSLayoutConstraint.activate([
      fileButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      fileButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      fileButton.topAnchor.constraint(equalTo: topAnchor),
      fileButton.heightAnchor.constraint(equalToConstant: 36),
      captionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      captionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      captionView.topAnchor.constraint(equalTo: fileButton.bottomAnchor, constant: 10),
    ])
  }

  static func supports(content: MsgLikeContent) -> Bool {
    guard case .message(let message) = content.kind else { return false }
    if case .file = message.msgType {
      return true
    }
    return false
  }

  func configure(content: MsgLikeContent, matrixClient: MatrixClient?) {
    guard case .message(let message) = content.kind,
      case .file(let file) = message.msgType
    else { return }

    configure(file: file, matrixClient: matrixClient)
  }

  func configure(file: FileMessageContent, matrixClient: MatrixClient?) {
    fileContent = file
    self.matrixClient = matrixClient
    let mimeType = file.info?.mimetype.flatMap(UTType.init) ?? .data
    fileButton.configure(
      icon: NSWorkspace.shared.icon(for: mimeType),
      filename: file.filename,
      size: file.info?.size?.formatted(.byteCount(style: .file))
    )

    let hasCaption = file.caption?.isEmpty == false || file.formattedCaption != nil
    captionView.isHidden = !hasCaption
    captionView.configureCaption(file.caption, formatted: file.formattedCaption)
    fileBottomConstraint.isActive = !hasCaption
    captionBottomConstraint.isActive = hasCaption

    let url = file.source.url()
    if sourceURL != url {
      previewTask?.cancel()
      previewTask = nil
      sourceURL = url
      fileButton.isEnabled = true
    }
  }

  func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
    guard case .message(let message) = content.kind,
      case .file(let file) = message.msgType
    else { return 0 }
    return height(for: file, width: width)
  }

  func height(for file: FileMessageContent, width: CGFloat) -> CGFloat {
    guard file.caption?.isEmpty == false || file.formattedCaption != nil else { return 36 }
    return 36 + 10
      + ceil(
        captionView.height(forCaption: file.caption, formatted: file.formattedCaption, width: width)
      )
  }

  @objc private func previewFile() {
    guard let fileContent, let window else { return }
    if onMediaPreviewRequest?() == true { return }
    guard let matrixClient else { return }
    let url = fileContent.source.url()
    fileButton.isEnabled = false
    previewTask?.cancel()
    previewTask = Task { [weak self, weak window] in
      do {
        let handle = try await matrixClient.client.getMediaFile(
          mediaSource: fileContent.source,
          filename: fileContent.filename,
          mimeType: fileContent.info?.mimetype ?? "",
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
        self.fileButton.setIcon(NSWorkspace.shared.icon(forFile: path))
        self.fileButton.isEnabled = true
        self.previewTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.sourceURL == url else { return }
        Logger.viewCycle.error("failed to preview file: \(error)")
        self.fileButton.isEnabled = true
        self.previewTask = nil
      }
    }
  }

  func resetMedia() {
    previewTask?.cancel()
    previewTask = nil
    sourceURL = nil
    fileContent = nil
    matrixClient = nil
  }

  deinit { previewTask?.cancel() }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class FilePreviewButton: NSButton {
  private let iconView = NSImageView()
  private let filenameLabel = NSTextField(labelWithString: "")
  private let sizeLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    isBordered = false
    title = ""
    iconView.imageScaling = .scaleProportionallyDown
    filenameLabel.lineBreakMode = .byTruncatingMiddle
    filenameLabel.maximumNumberOfLines = 1
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

    for view in [iconView, filenameLabel, sizeLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
      iconView.topAnchor.constraint(equalTo: topAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 36),
      iconView.heightAnchor.constraint(equalToConstant: 36),
      filenameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
      filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      filenameLabel.topAnchor.constraint(equalTo: topAnchor),
      sizeLabel.leadingAnchor.constraint(equalTo: filenameLabel.leadingAnchor),
      sizeLabel.trailingAnchor.constraint(equalTo: filenameLabel.trailingAnchor),
      sizeLabel.topAnchor.constraint(equalTo: filenameLabel.bottomAnchor, constant: 2),
    ])
  }

  func configure(icon: NSImage, filename: String, size: String?) {
    iconView.image = icon
    filenameLabel.stringValue = filename
    sizeLabel.stringValue = size ?? ""
    sizeLabel.isHidden = size == nil
    toolTip = "Preview \(filename)"
  }

  func setIcon(_ icon: NSImage) {
    iconView.image = icon
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    alphaValue = 0.6
    window?.displayIfNeeded()
    super.mouseDown(with: event)
    alphaValue = 1
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

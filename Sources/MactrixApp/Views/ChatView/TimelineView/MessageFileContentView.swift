import AppKit
import MatrixIntegration
import MatrixRustSDK
import OSLog
import UniformTypeIdentifiers

final class MessageFileContentView: NSView, MessageMediaPreviewContentView {
  var onMediaPreviewRequest: (() -> Bool)?
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)?
  var onFocusUser: ((String) -> Void)? {
    didSet { captionView.onFocusUser = onFocusUser }
  }
  var onSelectRequest: (() -> Void)? {
    didSet { captionView.onSelectRequest = onSelectRequest }
  }

  var onArrowKey: ((TimelineSelectionDirection) -> Void)? {
    didSet { captionView.onArrowKey = onArrowKey }
  }

  private let fileButton = FilePreviewButton()
  private let captionView = MessageTextContentView()
  private var fileHeightConstraint: NSLayoutConstraint!
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

    fileHeightConstraint = fileButton.heightAnchor.constraint(
      equalToConstant: FilePreviewButton.contentHeight)
    fileBottomConstraint = fileButton.bottomAnchor.constraint(equalTo: bottomAnchor)
    captionBottomConstraint = captionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    fileBottomConstraint.priority = .init(999)
    captionBottomConstraint.priority = .init(999)
    NSLayoutConstraint.activate([
      fileButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      fileButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      fileButton.topAnchor.constraint(equalTo: topAnchor),
      fileHeightConstraint,
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
    fileHeightConstraint.constant = FilePreviewButton.contentHeight
    let mimeType = file.info?.mimetype.flatMap(UTType.init) ?? .data
    fileButton.configure(
      icon: NSWorkspace.shared.icon(for: mimeType),
      filename: file.filename,
      size: file.info?.size?.formatted(.byteCount(style: .file))
    )

    let hasCaption =
      captionView.isEditing || file.caption?.isEmpty == false || file.formattedCaption != nil
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

  func configureEditing(_ state: MessageEditState?) {
    captionView.configureEditing(state)
    let hasCaption =
      state != nil || fileContent?.caption?.isEmpty == false
      || fileContent?.formattedCaption != nil
    fileBottomConstraint.isActive = false
    captionBottomConstraint.isActive = false
    captionView.isHidden = !hasCaption
    fileBottomConstraint.isActive = !hasCaption
    captionBottomConstraint.isActive = hasCaption
    needsLayout = true
  }

  func height(for content: MsgLikeContent, width: CGFloat) -> CGFloat {
    guard case .message(let message) = content.kind,
      case .file(let file) = message.msgType
    else { return 0 }
    return height(for: file, width: width)
  }

  func height(for file: FileMessageContent, width: CGFloat) -> CGFloat {
    guard captionView.isEditing || file.caption?.isEmpty == false || file.formattedCaption != nil
    else { return FilePreviewButton.contentHeight }
    return FilePreviewButton.contentHeight + 10
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
  private static var iconSize: CGFloat { TimelineTypography.scaled(36) }
  private static var filenameFont: NSFont {
    .systemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
  }

  private static var sizeFont: NSFont {
    .systemFont(ofSize: TimelineTypography.scaled(NSFont.smallSystemFontSize))
  }

  static var contentHeight: CGFloat {
    let filenameHeight = NSAttributedString(string: "Ag", attributes: [.font: filenameFont]).size()
      .height
    let sizeHeight = NSAttributedString(string: "Ag", attributes: [.font: sizeFont]).size().height
    return max(ceil(iconSize), ceil(filenameHeight) + 2 + ceil(sizeHeight))
  }

  private let iconView = NSImageView()
  private lazy var iconWidthConstraint = iconView.widthAnchor.constraint(
    equalToConstant: Self.iconSize)
  private lazy var iconHeightConstraint = iconView.heightAnchor.constraint(
    equalToConstant: Self.iconSize)
  private let filenameLabel = NSTextField(labelWithString: "")
  private let sizeLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    isBordered = false
    title = ""
    iconView.imageScaling = .scaleProportionallyUpOrDown
    filenameLabel.lineBreakMode = .byTruncatingMiddle
    filenameLabel.maximumNumberOfLines = 1
    sizeLabel.textColor = .secondaryLabelColor
    filenameLabel.font = Self.filenameFont
    sizeLabel.font = Self.sizeFont

    for view in [iconView, filenameLabel, sizeLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
      iconView.topAnchor.constraint(equalTo: topAnchor),
      iconWidthConstraint,
      iconHeightConstraint,
      filenameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
      filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      filenameLabel.topAnchor.constraint(equalTo: topAnchor),
      sizeLabel.leadingAnchor.constraint(equalTo: filenameLabel.leadingAnchor),
      sizeLabel.trailingAnchor.constraint(equalTo: filenameLabel.trailingAnchor),
      sizeLabel.topAnchor.constraint(equalTo: filenameLabel.bottomAnchor, constant: 2),
    ])
  }

  func configure(icon: NSImage, filename: String, size: String?) {
    iconWidthConstraint.constant = Self.iconSize
    iconHeightConstraint.constant = Self.iconSize
    filenameLabel.font = Self.filenameFont
    sizeLabel.font = Self.sizeFont
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

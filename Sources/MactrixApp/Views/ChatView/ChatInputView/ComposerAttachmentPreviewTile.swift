import AppKit

extension ComposerAttachment {
  var usesThumbnail: Bool {
    self.preview != nil && (self.kind == .image || self.kind == .video)
  }
}

final class ComposerAttachmentPreviewTile: NSView {
  static let sideLength: CGFloat = 72
  static let height: CGFloat = 90

  private(set) var attachment: ComposerAttachment
  var onRemove: (() -> Void)?
  var onPreview: (() -> Void)?

  private let previewButton = AttachmentPreviewButton()
  private let removeButton = NSButton()
  private let filenameLabel = NSTextField(labelWithString: "")

  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize {
    NSSize(width: Self.sideLength, height: Self.height)
  }

  init(attachment: ComposerAttachment) {
    self.attachment = attachment
    super.init(frame: NSRect(x: 0, y: 0, width: Self.sideLength, height: Self.height))

    previewButton.isBordered = false
    previewButton.setButtonType(.momentaryChange)
    previewButton.target = self
    previewButton.action = #selector(previewAttachment)
    addSubview(previewButton)

    removeButton.isBordered = false
    removeButton.setButtonType(.momentaryChange)
    removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
    removeButton.imagePosition = .imageOnly
    removeButton.wantsLayer = true
    removeButton.layer?.cornerRadius = 10
    removeButton.target = self
    removeButton.action = #selector(removeAttachment)
    addSubview(removeButton)

    filenameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
    filenameLabel.alignment = .center
    filenameLabel.lineBreakMode = .byTruncatingMiddle
    filenameLabel.maximumNumberOfLines = 1
    filenameLabel.cell?.wraps = false
    filenameLabel.cell?.isScrollable = false
    addSubview(filenameLabel)

    update(attachment: attachment)
    unregisterAttachmentDragTypes(in: self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    previewButton.frame = NSRect(x: 0, y: 0, width: Self.sideLength, height: Self.sideLength)
    removeButton.frame = NSRect(x: Self.sideLength - 23, y: 3, width: 20, height: 20)
    filenameLabel.frame = NSRect(
      x: 5, y: Self.sideLength + 4, width: Self.sideLength - 10, height: 14)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    removeButton.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
  }

  func update(attachment: ComposerAttachment) {
    self.attachment = attachment
    previewButton.previewImage = attachment.preview
    previewButton.usesThumbnail = attachment.usesThumbnail
    previewButton.fileIcon = NSWorkspace.shared.icon(for: attachment.contentType)
    previewButton.isVideo = attachment.kind == .video
    previewButton.needsDisplay = true
    filenameLabel.stringValue = attachment.filename
    filenameLabel.toolTip = attachment.filename
    // The preview button already exposes the filename to assistive technology.
    filenameLabel.setAccessibilityElement(false)

    let typeDescription: String
    switch attachment.kind {
    case .image: typeDescription = "image"
    case .video: typeDescription = "video"
    case .audio: typeDescription = "audio"
    case .file: typeDescription = "file"
    }
    let tooltip: String
    if let byteCount = attachment.byteCount {
      tooltip = "\(attachment.filename) (\(byteCount.formatted(.byteCount(style: .file))))"
    } else {
      tooltip = attachment.filename
    }
    previewButton.toolTip = tooltip
    previewButton.setAccessibilityLabel("\(attachment.filename), \(typeDescription), \(tooltip)")
    previewButton.setAccessibilityHelp("Open in Quick Look")
    removeButton.toolTip = "Remove \(attachment.filename)"
    removeButton.setAccessibilityLabel("Remove \(attachment.filename)")
    removeButton.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
  }

  @objc private func previewAttachment() { onPreview?() }
  @objc private func removeAttachment() { onRemove?() }
}

private final class AttachmentPreviewButton: NSButton {
  var previewImage: NSImage?
  var fileIcon: NSImage?
  var usesThumbnail = false
  var isVideo = false

  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()

    if let image = usesThumbnail ? previewImage : fileIcon,
      image.size.width > 0, image.size.height > 0
    {
      let widthScale = bounds.width / image.size.width
      let heightScale = bounds.height / image.size.height
      let scale = usesThumbnail ? max(widthScale, heightScale) : min(widthScale, heightScale)
      let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
      let rect = NSRect(
        x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
        width: size.width, height: size.height)
      image.draw(
        in: rect, from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.7 : 1,
        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    if isVideo {
      let overlay = NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
      NSColor.black.withAlphaComponent(0.45).setFill()
      NSBezierPath(ovalIn: overlay.insetBy(dx: 2, dy: 2)).fill()
      NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(paletteColors: [.white]))?
        .draw(
          in: overlay, from: .zero, operation: .sourceOver, fraction: 1,
          respectFlipped: true, hints: nil)
    }
  }
}

final class ComposerAttachmentPreviewStrip: NSScrollView {
  static let height = ComposerAttachmentPreviewTile.height

  var onRemove: ((ComposerAttachment.ID) -> Void)?
  var onPreview: ((ComposerAttachment.ID) -> Void)?
  private(set) var tiles: [ComposerAttachmentPreviewTile] = []

  private let tileContainer = AttachmentPreviewDocumentView()
  private let spacing: CGFloat = 8
  private let horizontalInset: CGFloat = 10

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    drawsBackground = false
    borderType = .noBorder
    hasHorizontalScroller = false
    hasVerticalScroller = false
    horizontalScrollElasticity = .allowed
    verticalScrollElasticity = .none
    documentView = tileContainer
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Attachments")
    unregisterAttachmentDragTypes(in: self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
  }

  func update(attachments: [ComposerAttachment]) {
    let existing = Dictionary(uniqueKeysWithValues: tiles.map { ($0.attachment.id, $0) })
    let retainedIDs = Set(attachments.map(\.id))
    for tile in tiles where !retainedIDs.contains(tile.attachment.id) {
      tile.onRemove = nil
      tile.onPreview = nil
      tile.removeFromSuperview()
    }
    tiles = attachments.map { attachment in
      let tile = existing[attachment.id] ?? ComposerAttachmentPreviewTile(attachment: attachment)
      tile.update(attachment: attachment)
      tile.onRemove = { [weak self] in self?.onRemove?(attachment.id) }
      tile.onPreview = { [weak self] in self?.onPreview?(attachment.id) }
      if tile.superview !== tileContainer { tileContainer.addSubview(tile) }
      return tile
    }
    layoutTiles()
    unregisterAttachmentDragTypes(in: self)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    layoutTiles()
  }

  private func layoutTiles() {
    let origin = contentView.bounds.origin
    let contentWidth =
      horizontalInset * 2 + CGFloat(tiles.count) * ComposerAttachmentPreviewTile.sideLength
      + CGFloat(max(0, tiles.count - 1)) * spacing
    tileContainer.setFrameSize(
      NSSize(width: max(contentView.bounds.width, contentWidth), height: Self.height))
    for (index, tile) in tiles.enumerated() {
      tile.frame = NSRect(
        x: horizontalInset + CGFloat(index) * (ComposerAttachmentPreviewTile.sideLength + spacing),
        y: 0, width: ComposerAttachmentPreviewTile.sideLength, height: Self.height)
    }
    let maxX = max(0, tileContainer.bounds.width - contentView.bounds.width)
    contentView.scroll(to: NSPoint(x: min(max(0, origin.x), maxX), y: 0))
    reflectScrolledClipView(contentView)
  }
}

private final class AttachmentPreviewDocumentView: NSView {
  override var isFlipped: Bool { true }
}

// NSScrollView and its clip view can register drag types of their own. Leave the
// entire subtree unregistered so attachment drags reach the composer container.
@MainActor
private func unregisterAttachmentDragTypes(in view: NSView) {
  view.unregisterDraggedTypes()
  for subview in view.subviews {
    unregisterAttachmentDragTypes(in: subview)
  }
}

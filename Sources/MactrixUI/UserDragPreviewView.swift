import AppKit

@MainActor
public final class UserDragPreviewView: NSView {
  private let avatarView: AvatarView
  private let usernameLabel = NSTextField(labelWithString: "")

  public init(
    userID: String,
    username: String,
    avatarView: AvatarView,
    avatarSize: CGFloat = 32,
    font: NSFont = .boldSystemFont(ofSize: NSFont.systemFontSize)
  ) {
    self.avatarView = avatarView.makePresentationCopy()
    super.init(frame: .zero)

    usernameLabel.stringValue = username
    usernameLabel.font = font
    usernameLabel.textColor = NSColor(userID: userID)
    usernameLabel.lineBreakMode = .byTruncatingTail
    usernameLabel.maximumNumberOfLines = 1
    usernameLabel.sizeToFit()

    let labelSize = NSSize(
      width: min(240, ceil(usernameLabel.frame.width)),
      height: ceil(usernameLabel.frame.height)
    )
    let height = max(avatarSize, labelSize.height)
    frame.size = NSSize(width: avatarSize + 8 + labelSize.width, height: height)
    self.avatarView.frame = NSRect(
      x: 0, y: (height - avatarSize) / 2, width: avatarSize, height: avatarSize
    )
    usernameLabel.frame = NSRect(
      x: avatarSize + 8, y: (height - labelSize.height) / 2,
      width: labelSize.width, height: labelSize.height
    )

    addSubview(self.avatarView)
    addSubview(usernameLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public var avatarFrame: NSRect { avatarView.frame }

  public func makeDraggingImage(backingScaleFactor: CGFloat) -> NSImage? {
    layoutSubtreeIfNeeded()

    let scale = max(1, backingScaleFactor)
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(ceil(bounds.width * scale)),
        pixelsHigh: Int(ceil(bounds.height * scale)),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else { return nil }

    bitmap.size = bounds.size
    cacheDisplay(in: bounds, to: bitmap)

    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmap)
    return image
  }
}

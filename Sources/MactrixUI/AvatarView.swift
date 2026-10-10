import AppKit

func userAvatarColorName(userID: String) -> String {
  String(
    format: "Username%02d",
    userID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 16 + 1
  )
}

func userAvatarInitial(userID: String, displayName: String?) -> String? {
  (displayName ?? userID).uppercased().first(where: { $0 != "@" }).map(String.init)
}

extension NSColor {
  public convenience init(userID: String) {
    self.init(named: userAvatarColorName(userID: userID))!
  }
}

public enum AvatarKind {
  case user, room
}

@MainActor
public final class AvatarView: NSView {
  private let initialLabel = NSTextField(labelWithString: "")
  private let imageView = AspectFillImageView()
  private var loadTask: Task<Void, Never>?
  private var avatarUrl: String?
  private var userID: String?
  private var kind: AvatarKind = .user

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.masksToBounds = true

    initialLabel.alignment = .center

    updateColors()

    addSubview(initialLabel)
    addSubview(imageView)
  }

  public override var intrinsicContentSize: NSSize {
    NSSize(width: 22, height: 22)
  }

  public override func layout() {
    super.layout()
    configureCornerRadius()
    initialLabel.font = .boldSystemFont(ofSize: min(bounds.width, bounds.height) * 0.7)
    initialLabel.sizeToFit()
    initialLabel.setFrameOrigin(
      NSPoint(
        x: bounds.midX - initialLabel.frame.width / 2,
        y: bounds.midY - initialLabel.frame.height / 2
      )
    )
    imageView.frame = bounds
    imageView.needsDisplay = true
  }

  override public func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      initialLabel.textColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8)
      if let userID {
        layer?.backgroundColor =
          if kind == .user {
            NSColor(userID: userID).cgColor
          } else {
            .clear
          }
      }
    }
  }

  private func configureCornerRadius() {
    switch kind {
    case .user:
      layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    case .room:
      layer?.cornerRadius = min(bounds.width, bounds.height) / 4
    }
  }

  public override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  public func configure(
    userID: String, displayName: String?, avatarUrl: String?, kind: AvatarKind,
    imageLoader: ImageLoader?
  ) {
    cancelLoad()
    self.avatarUrl = avatarUrl
    self.kind = kind
    self.userID = userID
    imageView.image = nil
    initialLabel.stringValue =
      if kind == .user {
        userAvatarInitial(userID: userID, displayName: displayName) ?? ""
      } else {
        ""
      }
    updateColors()
    configureCornerRadius()
    needsLayout = true

    guard let avatarUrl, let imageLoader else { return }
    if let cached = imageLoader.cachedImage(matrixUrl: avatarUrl) {
      imageView.image = cached
      return
    }

    loadTask = Task { [weak self] in
      guard let image = try? await imageLoader.loadImage(matrixUrl: avatarUrl, size: nil),
        !Task.isCancelled,
        let self,
        self.avatarUrl == avatarUrl
      else { return }
      self.imageView.image = image
    }
  }

  public func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class AspectFillImageView: NSImageView {
  override var intrinsicContentSize: NSSize {
    return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let image, image.size.width > 0, image.size.height > 0 else { return }

    let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let destination = NSRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )

    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    image.draw(
      in: destination,
      from: .zero,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
  }
}

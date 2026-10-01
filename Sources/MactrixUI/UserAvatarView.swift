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

@MainActor
public final class UserAvatarView: NSView {
  private let initialLabel = NSTextField(labelWithString: "")
  private let imageView = AspectFillImageView()
  private var loadTask: Task<Void, Never>?
  private var avatarUrl: String?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.masksToBounds = true

    initialLabel.alignment = .center
    initialLabel.textColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8)
    initialLabel.translatesAutoresizingMaskIntoConstraints = false
    imageView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(initialLabel)
    addSubview(imageView)
    NSLayoutConstraint.activate([
      initialLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      initialLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  public override var intrinsicContentSize: NSSize {
    NSSize(width: 22, height: 22)
  }

  public override func layout() {
    super.layout()
    layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    initialLabel.font = .boldSystemFont(ofSize: bounds.width * 0.7)
  }

  public override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  public func configure(
    userID: String, displayName: String?, avatarUrl: String?, imageLoader: ImageLoader?
  ) {
    cancelLoad()
    self.avatarUrl = avatarUrl
    imageView.image = nil
    initialLabel.stringValue = userAvatarInitial(userID: userID, displayName: displayName) ?? ""
    layer?.backgroundColor = NSColor(userID: userID).cgColor

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

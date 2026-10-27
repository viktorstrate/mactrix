import AppKit
import MactrixUI
import MatrixRustSDK

class MessageProfileRowView: NSView {
  let profilePicture = ProfilePictureButton()
  let name = NSTextField(labelWithString: "")
  private static var avatarSize: CGFloat { TimelineTypography.scaled(32) }
  private lazy var avatarTrailingConstraint = profilePicture.trailingAnchor.constraint(
    equalTo: leadingAnchor, constant: TimelineTypography.timestampColumnWidth)
  private lazy var avatarWidthConstraint = profilePicture.widthAnchor.constraint(
    equalToConstant: Self.avatarSize)
  private lazy var avatarHeightConstraint = profilePicture.heightAnchor.constraint(
    equalToConstant: Self.avatarSize)

  static var rowHeight: Double {
    max(32, Double(ceil(TimelineTypography.scaled(32))))
  }

  private var dragPayload: UserDragPayload?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    name.translatesAutoresizingMaskIntoConstraints = false
    name.isSelectable = true
    name.drawsBackground = false
    name.font = .boldSystemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
    name.lineBreakMode = .byTruncatingTail
    name.maximumNumberOfLines = 1

    profilePicture.onBeginUserDrag = { [weak self] dragEvent in
      self?.beginUserDrag(with: dragEvent)
    }

    addSubview(profilePicture)
    addSubview(name)

    NSLayoutConstraint.activate([
      avatarTrailingConstraint,
      profilePicture.centerYAnchor.constraint(equalTo: centerYAnchor),
      avatarWidthConstraint,
      avatarHeightConstraint,

      name.leadingAnchor.constraint(equalTo: profilePicture.trailingAnchor, constant: 16),
      name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
      name.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func initialize(
    imageLoader: MactrixUI.ImageLoader?, focusUser: @escaping (_ sender: String) -> Void
  ) {
    profilePicture.initialize(imageLoader: imageLoader, focusUser: focusUser)
  }

  func configure(event: EventTimelineItem) {
    avatarTrailingConstraint.constant = TimelineTypography.timestampColumnWidth
    avatarWidthConstraint.constant = Self.avatarSize
    avatarHeightConstraint.constant = Self.avatarSize
    name.font = .boldSystemFont(ofSize: TimelineTypography.scaled(NSFont.systemFontSize))
    let username: String
    let avatarUrl: String?
    switch event.senderProfile {
    case .ready(let profileDisplayName, _, let profileAvatarUrl, _, _):
      username = profileDisplayName ?? event.sender
      avatarUrl = profileAvatarUrl
    default:
      username = event.sender
      avatarUrl = nil
    }

    name.stringValue = username
    name.textColor = NSColor(userID: event.sender)
    name.toolTip = username

    profilePicture.configure(event: event)

    dragPayload = UserDragPayload(
      userID: event.sender, username: username, avatarUrl: avatarUrl)
  }

}

extension MessageProfileRowView: NSDraggingSource {
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    switch context {
    case .outsideApplication, .withinApplication:
      return .copy
    @unknown default:
      return []
    }
  }

  private func beginUserDrag(with event: NSEvent) {
    guard let payload = dragPayload else { return }

    _ = try? UserDragging.begin(
      payload: payload,
      from: self,
      avatarView: profilePicture.avatarView,
      event: event,
      source: self
    )
  }
}

class ProfilePictureButton: NSButton {

  let avatarView = AvatarView()
  private var sender: String?
  private var focusUserAction: (_ sender: String) -> Void = { _ in }
  private var imageLoader: MactrixUI.ImageLoader?

  var onBeginUserDrag: ((NSEvent) -> Void)? = nil

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    target = self
    action = #selector(onProfileClicked)
    title = ""
    isBordered = false

    avatarView.frame = bounds
    avatarView.autoresizingMask = [.width, .height]
    addSubview(avatarView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func initialize(
    imageLoader: MactrixUI.ImageLoader?, focusUser: @escaping (_ sender: String) -> Void
  ) {
    self.imageLoader = imageLoader
    focusUserAction = focusUser
  }

  func configure(event: EventTimelineItem) {
    sender = event.sender

    let displayName: String?
    let avatarUrl: String?
    switch event.senderProfile {
    case .ready(let profileDisplayName, _, let profileAvatarUrl, _, _):
      displayName = profileDisplayName
      avatarUrl = profileAvatarUrl
    default:
      displayName = nil
      avatarUrl = nil
    }

    avatarView.configure(
      userID: event.sender, displayName: displayName, avatarUrl: avatarUrl, kind: .user,
      imageLoader: imageLoader
    )
  }

  @objc func onProfileClicked(_ target: Any) {
    if let sender {
      focusUserAction(sender)
    }
  }

  override var isHighlighted: Bool {
    didSet {
      avatarView.alphaValue = isHighlighted ? 0.6 : 1
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }

    guard let window, let onBeginUserDrag else {
      super.mouseDown(with: event)
      return
    }

    isHighlighted = true
    defer { isHighlighted = false }
    window.displayIfNeeded()

    let startPoint = event.locationInWindow

    while let nextEvent = window.nextEvent(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) {
      let currentPoint = nextEvent.locationInWindow

      switch nextEvent.type {
      case .leftMouseDragged:
        isHighlighted = bounds.contains(convert(currentPoint, from: nil))

        let distance = hypot(
          currentPoint.x - startPoint.x,
          currentPoint.y - startPoint.y
        )

        guard distance >= 4 else { continue }

        // Capture the normal avatar appearance, not its pressed state.
        isHighlighted = false

        onBeginUserDrag(nextEvent)
        return

      case .leftMouseUp:
        let point = convert(currentPoint, from: nil)
        isHighlighted = false

        if bounds.contains(point), isEnabled {
          sendAction(action, to: target)
        }

        return

      default:
        break
      }
    }
  }
}

import AppKit
import MactrixUI
import MatrixRustSDK

class MessageProfileRowView: NSView {
  let profilePicture = ProfilePictureButton()
  let name = NSTextField(labelWithString: "")

  static let rowHeight: Double = 32

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    name.translatesAutoresizingMaskIntoConstraints = false
    name.isSelectable = true
    name.drawsBackground = false
    name.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    name.lineBreakMode = .byTruncatingTail
    name.maximumNumberOfLines = 1

    addSubview(profilePicture)
    addSubview(name)

    NSLayoutConstraint.activate([
      profilePicture.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      profilePicture.centerYAnchor.constraint(equalTo: centerYAnchor),
      profilePicture.widthAnchor.constraint(equalToConstant: 32),
      profilePicture.heightAnchor.constraint(equalToConstant: 32),

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
    let username: String
    switch event.senderProfile {
    case .ready(let profileDisplayName, _, _, _, _):
      username = profileDisplayName ?? event.sender
    default:
      username = event.sender
    }

    name.stringValue = username
    name.textColor = NSColor(userID: event.sender)
    name.toolTip = username

    profilePicture.configure(event: event)
  }

}

class ProfilePictureButton: NSButton {

  private let avatarView = UserAvatarView()
  private var sender: String?
  private var focusUserAction: (_ sender: String) -> Void = { _ in }
  private var imageLoader: MactrixUI.ImageLoader?

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
      userID: event.sender, displayName: displayName, avatarUrl: avatarUrl,
      imageLoader: imageLoader
    )
  }

  @objc func onProfileClicked(_ target: Any) {
    if let sender {
      focusUserAction(sender)
    }
  }

  override func mouseDown(with event: NSEvent) {
    alphaValue = 0.6
    window?.displayIfNeeded()
    super.mouseDown(with: event)
    alphaValue = 1
  }
}

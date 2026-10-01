import AppKit
import MactrixUI
import MatrixRustSDK

class MessageProfileRowView: NSView {
  let profilePicture = NSButton()
  let name = NSTextField(labelWithString: "")

  private let avatarView = UserAvatarView()
  private var sender: String?
  private var focusUserAction: (_ sender: String) -> Void = { _ in }
  private var imageLoader: MactrixUI.ImageLoader?

  static let rowHeight: Double = 32

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    profilePicture.target = self
    profilePicture.action = #selector(onProfileClicked)
    profilePicture.translatesAutoresizingMaskIntoConstraints = false
    profilePicture.title = ""
    profilePicture.isBordered = false

    avatarView.frame = profilePicture.bounds
    avatarView.autoresizingMask = [.width, .height]
    profilePicture.addSubview(avatarView)

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
    self.imageLoader = imageLoader
    focusUserAction = focusUser
  }

  func configure(event: EventTimelineItem) {
    sender = event.sender

    let username: String
    let displayName: String?
    let avatarUrl: String?
    switch event.senderProfile {
    case .ready(let profileDisplayName, _, let profileAvatarUrl, _, _):
      displayName = profileDisplayName
      username = profileDisplayName ?? event.sender
      avatarUrl = profileAvatarUrl
    default:
      displayName = nil
      username = event.sender
      avatarUrl = nil
    }

    name.stringValue = username
    name.textColor = NSColor(userID: event.sender)
    name.toolTip = username

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

}

import AppKit
import MatrixRustSDK
import UI

class MessageProfileRowView: NSView {
    let profilePicture = NSButton()
    let name = NSTextField()

    private var sender: String?
    private var focusUserAction: (_ sender: String) -> Void = { _ in }
    private var imageLoader: UI.ImageLoader?

    private var avatarTask: Task<Void, Never>?
    private var avatarUrl: String?

    static let ROW_HEIGHT: Double = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        profilePicture.target = self
        profilePicture.action = #selector(onProfileClicked)
        profilePicture.translatesAutoresizingMaskIntoConstraints = false
        profilePicture.imageScaling = .scaleProportionallyDown
        profilePicture.imagePosition = .imageOnly
        profilePicture.isBordered = false
        profilePicture.wantsLayer = true
        profilePicture.layer?.cornerRadius = 16
        profilePicture.layer?.masksToBounds = true
        profilePicture.layer?.backgroundColor = NSColor.gray.cgColor

        name.translatesAutoresizingMaskIntoConstraints = false
        name.isSelectable = true
        name.isEditable = false
        name.isBordered = false
        name.drawsBackground = false
        name.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        name.lineBreakMode = .byTruncatingTail

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

    func initialize(imageLoader: UI.ImageLoader?, focusUser: @escaping (_ sender: String) -> Void) {
        self.imageLoader = imageLoader
        focusUserAction = focusUser
    }

    func configure(event: EventTimelineItem) {
        sender = event.sender

        let username: String
        switch event.senderProfile {
        case .ready(let displayName, _, let avatarUrl, _, _):
            username = displayName ?? event.sender
            self.avatarUrl = avatarUrl
        default:
            username = event.sender
            avatarUrl = nil
        }

        name.stringValue = username
        name.textColor = NSColor(userID: event.sender)
        name.toolTip = username

        reloadAvatar()
    }

    @objc func onProfileClicked(_ target: Any) {
        if let sender {
            focusUserAction(sender)
        }
    }

    private func reloadAvatar() {
        avatarTask?.cancel()
        profilePicture.image = nil
        guard let avatarUrl, let imageLoader else { return }

        if let cached = imageLoader.cachedImage(matrixUrl: avatarUrl) {
            profilePicture.image = cached
            return
        }

        avatarTask = Task { [weak self] in
            guard let image = try? await imageLoader.loadImage(matrixUrl: avatarUrl, size: nil),
                  !Task.isCancelled,
                  let self,
                  self.avatarUrl == avatarUrl else { return }

            self.profilePicture.image = image
        }
    }
}

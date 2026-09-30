import AppKit
import MactrixUI
import MatrixProtocols
import MatrixRustSDK

/// Reuses the visible receipt avatars as the table row is recycled.
final class MessageReadReceiptsView: NSButton {
  static let rowHeight: CGFloat = 18
  private static let countFont = NSFont.systemFont(ofSize: 11)
  var onFocusUser: ((String) -> Void)?
  var receiptCount: Int {
    receipts.count
  }

  private let countLabel = NSTextField(labelWithString: "")
  private var avatars: [ReceiptAvatarView] = []
  private var receipts: [(userId: String, date: Date?)] = []
  private var members: [String: MatrixRustSDK.RoomMember] = [:]
  private var imageLoader: MactrixUI.ImageLoader?
  private let receiptPopover = NSPopover()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    title = ""
    target = self
    action = #selector(showReceipts)
    countLabel.font = Self.countFont
    countLabel.textColor = .secondaryLabelColor
    countLabel.alignment = .right
    addSubview(countLabel)
  }

  func configure(
    receipts: [String: MatrixProtocols.Receipt], members: [MatrixRustSDK.RoomMember],
    imageLoader: MactrixUI.ImageLoader?
  ) {
    self.receipts = receipts.map { ($0.key, $0.value.timestamp) }
      .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    self.members = Dictionary(
      members.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
    self.imageLoader = imageLoader
    receiptPopover.close()

    let visible = Array(self.receipts.suffix(3))
    while avatars.count < visible.count {
      let avatar = ReceiptAvatarView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
      addSubview(avatar)
      avatars.append(avatar)
    }
    for (avatar, receipt) in zip(avatars, visible) {
      avatar.configure(
        userId: receipt.userId, avatarUrl: self.members[receipt.userId]?.avatarUrl,
        imageLoader: imageLoader)
      avatar.isHidden = false
    }
    for avatar in avatars.dropFirst(visible.count) {
      avatar.isHidden = true
      avatar.cancelLoad()
    }
    let hiddenCount = self.receipts.count - visible.count
    countLabel.stringValue = hiddenCount > 0 ? "+\(hiddenCount)" : ""
    countLabel.isHidden = hiddenCount == 0
    toolTip =
      "Read by "
      + self.receipts.map { self.members[$0.userId]?.displayName ?? $0.userId }.joined(
        separator: ", ")
    needsLayout = true
  }

  static func width(for count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    let visible = min(count, 3)
    let avatarsWidth = CGFloat(visible) * 14 - CGFloat(max(visible - 1, 0)) * 2
    return avatarsWidth + countWidth(for: count)
  }

  private static func countWidth(for count: Int) -> CGFloat {
    guard count > 3 else { return 0 }
    let text = "+\(count - 3)" as NSString
    return max(20, ceil(text.size(withAttributes: [.font: countFont]).width) + 6)
  }

  override func layout() {
    super.layout()
    var x: CGFloat = 0
    if !countLabel.isHidden {
      x = Self.countWidth(for: receipts.count)
      countLabel.frame = NSRect(x: 0, y: 2, width: x, height: 14)
    }
    for avatar in avatars where !avatar.isHidden {
      avatar.frame = NSRect(x: x, y: 2, width: 14, height: 14)
      x += 12
    }
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

  @objc private func showReceipts() {
    if receiptPopover.isShown {
      receiptPopover.close()
      return
    }
    let stack = FlippedReceiptStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8

    let header = NSTextField(
      labelWithString: receipts.count == 1 ? "Read by 1 person" : "Read by \(receipts.count) people"
    )
    header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    stack.addArrangedSubview(header)
    let width: CGFloat = 230
    for receipt in receipts.reversed() {
      let row = ReceiptPopoverRowButton(userId: receipt.userId)
      row.onClick = { [weak self] userId in
        self?.receiptPopover.close()
        self?.onFocusUser?(userId)
      }
      row.widthAnchor.constraint(equalToConstant: width - 24).isActive = true
      row.heightAnchor.constraint(equalToConstant: 36).isActive = true
      let content = row.content
      let avatar = ReceiptAvatarView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
      avatar.configure(
        userId: receipt.userId, avatarUrl: members[receipt.userId]?.avatarUrl,
        imageLoader: imageLoader)
      avatar.widthAnchor.constraint(equalToConstant: 28).isActive = true
      avatar.heightAnchor.constraint(equalToConstant: 28).isActive = true
      content.addArrangedSubview(avatar)

      let details = NSStackView()
      details.orientation = .vertical
      details.alignment = .leading
      details.spacing = 2
      let name = members[receipt.userId]?.displayName ?? receipt.userId
      let nameLabel = NSTextField(labelWithString: name)
      nameLabel.lineBreakMode = .byTruncatingTail
      nameLabel.toolTip = name
      details.addArrangedSubview(nameLabel)
      if let date = receipt.date {
        let dateLabel = NSTextField(labelWithString: Self.formattedTimestamp(date))
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabelColor
        details.addArrangedSubview(dateLabel)
      }
      content.addArrangedSubview(details)
      stack.addArrangedSubview(row)
    }
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = receipts.count > 6
    stack.frame = NSRect(x: 0, y: 0, width: width - 24, height: stack.fittingSize.height)
    scroll.documentView = stack
    scroll.frame = NSRect(
      x: 12, y: 12, width: width - 24, height: min(stack.fittingSize.height, 220))
    let container = NSView(
      frame: NSRect(x: 0, y: 0, width: width, height: scroll.frame.height + 24))
    container.addSubview(scroll)
    let controller = NSViewController()
    controller.view = container
    receiptPopover.contentViewController = controller
    receiptPopover.contentSize = container.bounds.size
    receiptPopover.behavior = .transient
    receiptPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
  }

  private static func formattedTimestamp(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
      return date.formatted(.dateTime.hour().minute())
    }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class FlippedReceiptStackView: NSStackView {
  override var isFlipped: Bool { true }
}

private final class ReceiptPopoverRowButton: NSButton {
  let content = NSStackView()
  var onClick: ((String) -> Void)?
  private let userId: String

  init(userId: String) {
    self.userId = userId
    super.init(frame: .zero)
    isBordered = false
    title = ""
    target = self
    action = #selector(activate)

    content.orientation = .horizontal
    content.alignment = .centerY
    content.spacing = 10
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
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

  @objc private func activate() {
    onClick?(userId)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class ReceiptAvatarView: NSImageView {
  private var loadTask: Task<Void, Never>?
  private var avatarUrl: String?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    imageScaling = .scaleProportionallyUpOrDown
    wantsLayer = true
    layer?.masksToBounds = true
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.width / 2
  }

  func configure(userId: String, avatarUrl: String?, imageLoader: MactrixUI.ImageLoader?) {
    cancelLoad()
    self.avatarUrl = avatarUrl
    image = nil
    layer?.backgroundColor = NSColor(userID: userId).cgColor
    guard let avatarUrl, let imageLoader else { return }
    if let cached = imageLoader.cachedImage(matrixUrl: avatarUrl) {
      image = cached
      return
    }
    loadTask = Task { [weak self] in
      guard let image = try? await imageLoader.loadImage(matrixUrl: avatarUrl, size: nil),
        !Task.isCancelled, let self, self.avatarUrl == avatarUrl
      else { return }
      self.image = image
    }
  }

  func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

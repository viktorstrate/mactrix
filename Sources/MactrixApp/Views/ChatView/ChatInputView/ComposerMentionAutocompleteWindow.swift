import AppKit
import MactrixUI
import MatrixProtocols

/// Presentation only: the editor owns the session, highlight, placement, and window lifetime.
@MainActor
final class ComposerMentionAutocompleteWindow: NSWindow {
  var onHighlight: ((String) -> Void)?
  var onSubmit: (() -> Void)?
  weak var imageLoader: ImageLoader?

  private static let rowHeight: CGFloat = 44
  private let scrollView = NSScrollView()
  private let tableView = MentionTableView()
  private var suggestions: [any MatrixProtocols.UserProfile] = []

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: Self.rowHeight),
      styleMask: [.borderless], backing: .buffered, defer: true)
    isReleasedWhenClosed = false
    hasShadow = true
    isOpaque = false
    backgroundColor = .clear
    collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
    isMovable = false
    hidesOnDeactivate = true

    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.rowHeight = Self.rowHeight
    tableView.intercellSpacing = .zero
    tableView.focusRingType = .none
    tableView.autoresizingMask = [.width]
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profile"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.onRowSelect = { [weak self] row in
      guard let self, suggestions.indices.contains(row) else { return }
      onHighlight?(suggestions[row].userId)
    }
    tableView.onRowClickUp = { [weak self] row in
      self?.onSubmit?()
    }

    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.documentView = tableView

    scrollView.wantsLayer = true
    scrollView.layer?.cornerRadius = 10
    scrollView.layer?.masksToBounds = true

    contentView = scrollView
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    let sizeChanged = frame.size != frameRect.size
    super.setFrame(frameRect, display: flag)
    guard sizeChanged else { return }
    // The owner can cap the viewport after update, so reveal the highlight again after resizing.
    scrollView.layoutSubtreeIfNeeded()
    if tableView.selectedRow >= 0 {
      tableView.scrollRowToVisible(tableView.selectedRow)
    }
  }

  var preferredSize: NSSize {
    NSSize(width: 320, height: CGFloat(min(suggestions.count, 6)) * Self.rowHeight)
  }

  /// Does not show, position, or resize the window, or invoke the owner's callback.
  func update(suggestions: [any MatrixProtocols.UserProfile], highlightedUserID: String?) {
    let contentsChanged = !self.suggestions.elementsEqual(suggestions) {
      $0.userId == $1.userId && $0.displayName == $1.displayName
    }
    self.suggestions = suggestions
    if contentsChanged { tableView.reloadData() }
    let highlightedRow = suggestions.firstIndex(where: { $0.userId == highlightedUserID })
    guard contentsChanged || tableView.selectedRow != (highlightedRow ?? -1) else { return }
    if let row = highlightedRow {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      scrollView.layoutSubtreeIfNeeded()
      tableView.scrollRowToVisible(row)
    } else {
      tableView.deselectAll(nil)
    }
  }

  /// Screen coordinates. If neither side fits, clamping can overlap the anchor.
  static func frame(anchoredTo anchor: NSRect, preferredSize: NSSize, visibleFrame: NSRect)
    -> NSRect
  {
    let bounds = visibleFrame.insetBy(
      dx: min(8, visibleFrame.width / 2), dy: min(8, visibleFrame.height / 2))
    let size = NSSize(
      width: min(max(0, preferredSize.width), bounds.width),
      height: min(max(0, preferredSize.height), bounds.height))
    let aboveY = anchor.maxY + 4
    let belowY = anchor.minY - 4 - size.height
    let belowFits = belowY >= bounds.minY && belowY + size.height <= bounds.maxY
    let y = aboveY + size.height > bounds.maxY && belowFits ? belowY : aboveY
    return NSRect(
      x: min(max(anchor.minX, bounds.minX), bounds.maxX - size.width),
      y: min(max(y, bounds.minY), bounds.maxY - size.height),
      width: size.width, height: size.height)
  }
}

extension ComposerMentionAutocompleteWindow: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    suggestions.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let profile = suggestions[row]
    let identifier = NSUserInterfaceItemIdentifier("mentionCell")
    let cell =
      tableView.makeView(withIdentifier: identifier, owner: self) as? MentionCellView
      ?? MentionCellView()
    cell.identifier = identifier
    cell.configure(profile: profile, imageLoader: imageLoader)
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    MentionRowView()
  }
}

/// Clicks request a highlight; only the next owner-driven update changes selection.
private final class MentionTableView: NSTableView {
  var onRowSelect: ((Int) -> Void)?
  var onRowClickUp: ((Int) -> Void)?

  private var mouseDownOnRow: Int?

  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    guard row >= 0 else { return }
    mouseDownOnRow = row
    // Do not call super: native table tracking would change selection and request focus.
    onRowSelect?(row)
  }

  override func mouseDragged(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    if row >= 0 && mouseDownOnRow != row {
      mouseDownOnRow = row
      onRowSelect?(row)
    }

    super.mouseDragged(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    if row >= 0 && mouseDownOnRow == row {
      onRowClickUp?(row)
    }
    mouseDownOnRow = nil

    super.mouseUp(with: event)
  }
}

private final class MentionRowView: NSTableRowView {
  // Route all row/label hits to the table rather than a text field or native row tracking.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override var isEmphasized: Bool {
    get { true }
    set {
      // Ignore AppKit's updates: the editor keeps keyboard focus.
    }
  }

  override func drawSelection(in dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 4, dy: 4)
    NSColor.selectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
  }
}

private final class MentionCellView: NSView {
  let avatar = AvatarView()
  let nameLabel = NSTextField(labelWithString: "")
  let idLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
    nameLabel.textColor = .labelColor
    idLabel.font = .systemFont(ofSize: 11)
    idLabel.textColor = .secondaryLabelColor
    for label in [nameLabel, idLabel] {
      label.isSelectable = false
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
      addSubview(label)
    }
    avatar.translatesAutoresizingMaskIntoConstraints = false
    addSubview(avatar)

    NSLayoutConstraint.activate([
      avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      avatar.centerYAnchor.constraint(equalTo: centerYAnchor),
      avatar.widthAnchor.constraint(equalToConstant: 28),
      avatar.heightAnchor.constraint(equalToConstant: 28),
      nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 6),
      nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
      idLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      idLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      idLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
    ])
  }

  func configure(profile: some UserProfile, imageLoader: any ImageLoader?) {
    avatar.configure(
      userID: profile.userId, displayName: profile.displayName, avatarUrl: profile.avatarUrl,
      kind: .user, imageLoader: imageLoader)
    nameLabel.stringValue = profile.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? profile.userId
    // nameLabel.textColor = NSColor(userID: profile.userId)
    idLabel.stringValue = profile.userId
  }

  required init?(coder: NSCoder) { return nil }
}

import AppKit
import ContactLinking
import MactrixUI
import Observation

protocol QuickNavigationContainer: NSView {
  init(navigationView: QuickNavigationView)
  var navigationView: QuickNavigationView { get }
}

@available(macOS 26.0, *)
final class QuickNavigationGlassView: NSGlassEffectView, QuickNavigationContainer {
  let navigationView: QuickNavigationView

  init(navigationView: QuickNavigationView) {
    self.navigationView = navigationView
    super.init(frame: NSRect(origin: .zero, size: navigationView.preferredSize))

    style = .regular
    cornerRadius = 16
    contentView = navigationView
  }

  required init?(coder: NSCoder) { return nil }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    super.updateLayer()
    tintColor = .controlBackgroundColor.withAlphaComponent(0.5)
  }
}

final class QuickNavigationFallbackView: NSView, QuickNavigationContainer {
  let navigationView: QuickNavigationView

  init(navigationView: QuickNavigationView) {
    self.navigationView = navigationView
    super.init(frame: NSRect(origin: .zero, size: navigationView.preferredSize))

    wantsLayer = true
    layer?.masksToBounds = false

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    self.shadow = shadow

    let effectView = NSVisualEffectView(
      frame: NSRect(origin: .zero, size: navigationView.preferredSize))
    effectView.material = .popover
    effectView.blendingMode = .withinWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 16
    effectView.layer?.masksToBounds = true

    navigationView.frame = bounds
    navigationView.autoresizingMask = [.width, .height]
    effectView.addSubview(navigationView)
    addSubview(effectView)
  }

  required init?(coder: NSCoder) { nil }
}

final class QuickNavigationView: NSView {
  static let rowHeight: CGFloat = 52
  private static let headerHeight: CGFloat = 64
  private static let resultsPadding: CGFloat = 8

  let session: QuickNavigationSession
  let searchField = NSTextField()
  let tableView = QuickNavigationTableView()
  let scrollView = NSScrollView()
  let emptyLabel = NSTextField(labelWithString: "No matching rooms")
  var onSubmit: ((QuickNavigationCandidate) -> Void)?
  var onDismiss: (() -> Void)?
  var onSearchFocusLost: (() -> Void)?
  var onPreferredSizeChange: (() -> Void)?
  weak var imageLoader: ImageLoader? {
    didSet { synchronize(reloadResults: true) }
  }

  var contactRevision = 0 {
    didSet {
      // Photos can change without changing any searchable candidate metadata.
      if contactRevision != oldValue { synchronize(reloadResults: true) }
    }
  }

  private var displayedResults: [QuickNavigationCandidate] = []
  private var displayedQuery = ""
  private var displayedHighlight: String?
  private var needsRevealSelection = false
  private var lastPreferredSize: NSSize = .zero
  private let scrollAnimation: QuickNavigationScrollAnimation

  init(session: QuickNavigationSession) {
    self.session = session
    self.scrollAnimation = QuickNavigationScrollAnimation(scrollView: scrollView)
    super.init(frame: .zero)

    let searchIcon = NSImageView()
    searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
    searchIcon.symbolConfiguration = .init(pointSize: 21, weight: .regular)
    searchIcon.contentTintColor = .secondaryLabelColor

    searchField.isBordered = false
    searchField.drawsBackground = false
    searchField.focusRingType = .none
    searchField.font = .systemFont(ofSize: 24)
    searchField.placeholderString = "Go to Room"
    searchField.usesSingleLineMode = true
    searchField.lineBreakMode = .byClipping
    searchField.cell?.isScrollable = true
    searchField.delegate = self
    searchField.setAccessibilityLabel("Search rooms")

    let separator = NSBox()
    separator.boxType = .separator

    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.backgroundColor = .clear
    tableView.rowHeight = Self.rowHeight
    tableView.intercellSpacing = .zero
    tableView.focusRingType = .none
    tableView.autoresizingMask = [.width]
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.setAccessibilityLabel("Rooms")
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("room"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.onHighlight = { [weak self] row in
      guard let self, displayedResults.indices.contains(row) else { return }
      session.highlight(roomID: displayedResults[row].id)
      synchronize()
    }
    tableView.onSubmit = { [weak self] row in
      guard let self, displayedResults.indices.contains(row),
        session.results.contains(where: { $0.id == displayedResults[row].id })
      else { return }
      session.highlight(roomID: displayedResults[row].id)
      submit()
    }

    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.documentView = tableView
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(
      top: Self.resultsPadding, left: 8, bottom: Self.resultsPadding, right: 8)

    emptyLabel.font = .systemFont(ofSize: 14)
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.alignment = .center

    for view in [searchIcon, searchField, separator, scrollView, emptyLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      searchIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
      searchIcon.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight / 2),
      searchIcon.widthAnchor.constraint(equalToConstant: 24),
      searchIcon.heightAnchor.constraint(equalToConstant: 24),
      searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 14),
      searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      searchField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
      separator.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight),
      separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      separator.heightAnchor.constraint(equalToConstant: 1),
      scrollView.topAnchor.constraint(equalTo: separator.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
    ])
    observeSession()
  }

  required init?(coder: NSCoder) { return nil }

  var preferredSize: NSSize {
    let rows = max(1, min(session.results.count, 8))
    return NSSize(
      width: 640,
      height: Self.headerHeight + 1 + 2 * Self.resultsPadding + CGFloat(rows) * Self.rowHeight)
  }

  override func layout() {
    super.layout()
    guard needsRevealSelection, window != nil else { return }
    // Initial synchronization can lay out a zero-sized view before presentation. Wait for the
    // scroll view's actual viewport so the first row doesn't become a stale downward target.
    scrollView.layoutSubtreeIfNeeded()
    let viewport = scrollView.contentView.bounds
    guard viewport.width > 0, viewport.height > 0 else { return }
    needsRevealSelection = false
    scrollAnimation.reveal(
      row: tableView.selectedRow, in: tableView, padding: Self.resultsPadding)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      scrollAnimation.cancel()
    } else if needsRevealSelection {
      needsLayout = true
    }
  }

  private func observeSession() {
    withObservationTracking {
      _ = session.query
      _ = session.results
      _ = session.highlightedRoomID
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSession() }
    }
    synchronize()
  }

  private func synchronize(reloadResults: Bool = false) {
    let orderChanged = !displayedResults.elementsEqual(session.results) { $0.id == $1.id }
    let revealSelection =
      orderChanged || displayedQuery != session.query
      || displayedHighlight != session.highlightedRoomID
    displayedQuery = session.query
    displayedHighlight = session.highlightedRoomID
    if orderChanged {
      tableView.cancelMouseTracking()
      scrollAnimation.cancel()
    }
    if searchField.stringValue != session.query,
      (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true
    {
      searchField.stringValue = session.query
    }
    if reloadResults || displayedResults != session.results {
      displayedResults = session.results
      tableView.reloadData()
    }
    emptyLabel.isHidden = !displayedResults.isEmpty
    scrollView.isHidden = displayedResults.isEmpty
    if let row = displayedResults.firstIndex(where: { $0.id == session.highlightedRoomID }) {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    } else {
      tableView.deselectAll(nil)
    }
    if revealSelection {
      needsRevealSelection = true
      needsLayout = true
    }
    let size = preferredSize
    if lastPreferredSize != size {
      lastPreferredSize = size
      onPreferredSizeChange?()
    }
    layoutSubtreeIfNeeded()
  }

  private func submit() {
    guard let candidate = session.highlightedCandidate else { return }
    onSubmit?(candidate)
  }
}

extension QuickNavigationView: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ notification: Notification) {
    onSearchFocusLost?()
  }

  func controlTextDidChange(_ notification: Notification) {
    guard (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
    session.updateQuery(searchField.stringValue)
    synchronize()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    // The field editor/input method must get first refusal while composing text.
    guard !textView.hasMarkedText() else { return false }
    switch commandSelector {
    case #selector(NSResponder.moveUp(_:)):
      session.moveSelection(.up)
    case #selector(NSResponder.moveDown(_:)):
      session.moveSelection(.down)
    case #selector(NSResponder.insertNewline(_:)):
      submit()
    case #selector(NSResponder.cancelOperation(_:)):
      onDismiss?()
    default:
      return false
    }
    synchronize()
    return true
  }
}

extension QuickNavigationView: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int { displayedResults.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let identifier = NSUserInterfaceItemIdentifier("quickNavigationCell")
    let cell =
      tableView.makeView(withIdentifier: identifier, owner: self) as? QuickNavigationCellView
      ?? QuickNavigationCellView()
    cell.identifier = identifier
    cell.configure(candidate: displayedResults[row], imageLoader: imageLoader)
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    QuickNavigationRowView()
  }
}

/// Track clicks without AppKit moving first responder away from the search field.
final class QuickNavigationTableView: NSTableView {
  var onHighlight: ((Int) -> Void)?
  var onSubmit: ((Int) -> Void)?
  private var mouseDownOnRow: Int?

  func cancelMouseTracking() {
    mouseDownOnRow = nil
  }

  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    mouseDownOnRow = row >= 0 ? row : nil
    if row >= 0 { onHighlight?(row) }
  }

  override func mouseDragged(with event: NSEvent) {
    guard mouseDownOnRow != nil else { return }
    let row = row(at: convert(event.locationInWindow, from: nil))
    if row >= 0 && mouseDownOnRow != row {
      mouseDownOnRow = row
      onHighlight?(row)
    }
    autoscroll(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    let shouldSubmit = row >= 0 && mouseDownOnRow == row
    mouseDownOnRow = nil
    if shouldSubmit { onSubmit?(row) }
  }
}

private final class QuickNavigationRowView: NSTableRowView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override var isEmphasized: Bool {
    get { true }
    set {}
  }

  override func drawSelection(in dirtyRect: NSRect) {
    NSColor.selectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 8, yRadius: 8).fill()
  }
}

final class QuickNavigationCellView: NSTableCellView {
  let avatar = AvatarView()
  let nameLabel = NSTextField(labelWithString: "")
  let detailLabel = NSTextField(labelWithString: "")
  private let fallbackIcon = NSImageView()

  init() {
    super.init(frame: .zero)
    nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
    detailLabel.font = .systemFont(ofSize: 12)

    fallbackIcon.symbolConfiguration = .init(pointSize: 22, weight: .medium)
    for label in [nameLabel, detailLabel] {
      label.isSelectable = false
      label.lineBreakMode = .byTruncatingTail
    }
    for view in [fallbackIcon, avatar, nameLabel, detailLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      avatar.centerYAnchor.constraint(equalTo: centerYAnchor),
      avatar.widthAnchor.constraint(equalToConstant: 32),
      avatar.heightAnchor.constraint(equalToConstant: 32),
      fallbackIcon.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
      fallbackIcon.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      fallbackIcon.widthAnchor.constraint(equalToConstant: 24),
      fallbackIcon.heightAnchor.constraint(equalToConstant: 24),
      nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
      nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
      detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
    ])
    updateColors()
  }

  required init?(coder: NSCoder) { return nil }

  override var backgroundStyle: NSView.BackgroundStyle {
    didSet { updateColors() }
  }

  private func updateColors() {
    let selected = backgroundStyle == .emphasized
    nameLabel.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
    detailLabel.textColor =
      selected
      ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85) : .secondaryLabelColor
    fallbackIcon.contentTintColor =
      selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
  }

  func configure(candidate: QuickNavigationCandidate, imageLoader: ImageLoader?) {
    nameLabel.stringValue = candidate.resolvedDisplayName
    detailLabel.stringValue =
      candidate.canonicalAlias.flatMap { $0.isEmpty ? nil : $0 } ?? candidate.id
    let avatarUrl = candidate.avatarUrl.flatMap { $0.isEmpty ? nil : $0 }
    let hasContactImage =
      candidate.directUserID.flatMap {
        ContactDirectory.shared.contactImage(for: $0)
      } != nil
    avatar.isHidden = avatarUrl == nil && !hasContactImage
    fallbackIcon.isHidden = !avatar.isHidden
    fallbackIcon.image = NSImage(
      systemSymbolName: candidate.kind.fallbackSymbolName, accessibilityDescription: nil)
    avatar.configure(
      userID: candidate.directUserID ?? candidate.id, displayName: candidate.resolvedDisplayName,
      avatarUrl: avatarUrl,
      kind: candidate.kind == .direct ? .user : .room, imageLoader: imageLoader)
  }
}

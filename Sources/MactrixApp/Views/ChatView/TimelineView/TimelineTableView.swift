import AppKit
import MatrixIntegration
import MatrixProtocols
import MatrixRustSDK
import OSLog

enum TimelineSelectionDirection {
  case up
  case down

  init?(event: NSEvent) {
    guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
      return nil
    }
    switch event.keyCode {
    case 126: self = .up
    case 125: self = .down
    default: return nil
    }
  }

  var rowStep: Int {
    self == .up ? 1 : -1
  }
}

enum TimelineItemRowInfo {
  case profile(item: TimelineItem, event: MatrixRustSDK.EventTimelineItem)
  case message(
    item: TimelineItem, event: MatrixRustSDK.EventTimelineItem,
    content: MatrixRustSDK.MsgLikeContent)
  case state(item: TimelineItem, event: MatrixRustSDK.EventTimelineItem)
  case virtual(item: TimelineItem, virtual: MatrixRustSDK.VirtualTimelineItem)
  case typingIndicator

  @MainActor
  var reuseIdentifier: NSUserInterfaceItemIdentifier {
    switch self {
    case .profile(profile: _):
      return NSUserInterfaceItemIdentifier("profile")
    case .message(_, _, let content):
      return MessageContentKind(content: content).reuseIdentifier
    case .state:
      return NSUserInterfaceItemIdentifier("state")
    case .virtual:
      return NSUserInterfaceItemIdentifier("virtual")
    case .typingIndicator:
      return NSUserInterfaceItemIdentifier("typing-indicator")
    }
  }
}

extension TimelineItemRowInfo: Identifiable {
  var id: String {
    switch self {
    case .profile(_, let event):
      "profile:\(event.eventOrTransactionId.id)"
    case .message(_, let event, _):
      "message:\(event.eventOrTransactionId.id)"
    case .state(_, let event):
      "state:\(event.eventOrTransactionId.id)"
    case .virtual(let item, _):
      "virtual:\(item.uniqueId().id)"
    case .typingIndicator:
      "typing-indicator"
    }
  }
}

class TimelineViewController: NSViewController, LiveTimelineFocusDelegate, LiveTimelineDiffDelegate
{
  let coordinator: TimelineViewRepresentable.Coordinator

  private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

  let scrollView = NSScrollView()
  let tableView = BottomStickyTableView()
  private let hoverOverlay = MessageHoverOverlayView()
  private weak var hoveredMessageView: MessageRowView?
  private var hoveredMessageId: String?
  private var hoveredRowIndex: Int?
  private var updatingTimelineItems = false

  let timeline: LiveTimeline
  private var projection: TimelineRowProjection
  var timelineItems: [TimelineItemRowInfo] {
    projection.rows
  }

  init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline) {
    self.coordinator = coordinator
    self.timeline = timeline
    self.projection = TimelineRowProjection(items: timeline.timelineItems)
    super.init(nibName: nil, bundle: nil)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    tableView.addTableColumn(NSTableColumn())
    tableView.headerView = nil
    tableView.style = .plain
    tableView.allowsColumnSelection = false
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.selectionHighlightStyle = .none

    // Every row is sized by tableView(_:heightOfRow:). Automatic heights can
    // collapse NSTextView rows because the view has no intrinsic height.
    tableView.rowSizeStyle = .custom
    tableView.rowHeight = 28
    tableView.usesAutomaticRowHeights = false
    tableView.onLayout = { [weak self] in
      self?.positionHoverOverlay()
    }
    tableView.onArrowKey = { [weak self] direction in
      self?.moveSelection(direction)
    }

    oldWidth = tableView.frame.width

    dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
      guard let self else { return NSView() }

      let item = self.timelineItems[row]

      switch item {
      case .profile(item: _, let event):
        if let recycledView = tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? MessageProfileRowView
        {
          recycledView.configure(event: event)
          return recycledView
        } else {
          let view = MessageProfileRowView()
          view.initialize(
            imageLoader: coordinator.appState.matrixClient,
            focusUser: { [weak self] in
              self?.coordinator.windowState.focusUser(userId: $0)
            })
          view.configure(event: event)
          view.identifier = item.reuseIdentifier
          return view
        }
      case .typingIndicator:
        let view =
          tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? TypingIndicatorRowView ?? TypingIndicatorRowView()
        view.configure(names: self.typingNames)
        view.identifier = item.reuseIdentifier
        return view
      case .virtual(_, let virtual):
        let view =
          tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? VirtualItemRowView ?? VirtualItemRowView()
        view.configure(item: virtual)
        view.identifier = item.reuseIdentifier
        return view
      case .state(_, let event):
        let view =
          tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? StateEventRowView ?? StateEventRowView()
        view.configure(event: event)
        view.identifier = item.reuseIdentifier
        return view
      case .message(_, let event, let content):
        let kind = MessageContentKind(content: content)
        let recycled =
          tableView.makeView(withIdentifier: kind.reuseIdentifier, owner: self) as? MessageRowView
        let view: MessageRowView
        if let recycled, recycled.contentKind == kind {
          view = recycled
        } else {
          view = kind.makeRowView()
        }
        view.onHoverChange = { [weak self] rowView, hovering, event in
          self?.updateHoverOverlay(for: rowView, hovering: hovering, event: event) ?? false
        }
        view.onSelectRequest = { [weak self] rowView in
          self?.selectMessageRow(for: rowView)
        }
        view.onArrowKey = { [weak self] direction in
          self?.moveSelection(direction)
        }
        view.configure(
          event: event,
          content: content,
          replyDetails: self.replyDetails(for: content),
          onReplyClick: self.replyClick(for: content),
          onThreadClick: { [weak self] in
            self?.coordinator.windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
          },
          ownUserId: try? self.coordinator.appState.matrixClient?.client.userId(),
          onReactionClick: { [weak self] key in
            self?.toggleReaction(key, for: event)
          },
          roomMembers: self.timeline.room.members,
          matrixClient: self.coordinator.appState.matrixClient,
          onFocusUser: { [weak self] userId in
            self?.coordinator.windowState.focusUser(userId: userId)
          }
        )
        view.setSelected(tableView.selectedRow == row)
        view.identifier = kind.reuseIdentifier
        return view
      }
    }

    tableView.delegate = self

    scrollView.documentView = tableView
    hoverOverlay.isHidden = true
    hoverOverlay.onMouseExited = { [weak self] event in
      self?.hoverOverlayDidExit(with: event)
    }
    hoverOverlay.onAction = { [weak self] action in
      self?.performHoverAction(action)
    }
    scrollView.contentView.addSubview(hoverOverlay, positioned: .above, relativeTo: tableView)
    scrollView.hasVerticalScroller = true

    scrollView.automaticallyAdjustsContentInsets = false

    scrollView.drawsBackground = false
    tableView.backgroundColor = .clear
    view = scrollView

    // Subscribe to view resize notifications
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTableResize),
      name: NSView.frameDidChangeNotification,
      object: scrollView.contentView
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(viewDidScroll(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )

    timeline.focusDelegate = self
    timeline.diffDelegate = self
    applyProjectedRows(oldIDs: [], changedIDs: [])
    listenForTypingUsers()
    listenForReplyDetails()
  }

  private func replyDetails(for content: MatrixRustSDK.MsgLikeContent) -> MatrixRustSDK
    .EmbeddedEventDetails?
  {
    guard let reply = content.inReplyTo else { return nil }
    return timeline.loadedReplyDetails[reply.eventId()]?.event() ?? reply.event()
  }

  private func replyClick(for content: MatrixRustSDK.MsgLikeContent) -> (() -> Void)? {
    guard let replyId = content.inReplyTo?.eventId() else { return nil }
    return { [weak self] in
      self?.timeline.focusEvent(id: .eventId(eventId: replyId))
    }
  }

  private func listenForReplyDetails() {
    withObservationTracking {
      _ = timeline.loadedReplyDetails
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.listenForReplyDetails()
        self.refreshVisibleReplyRows()
      }
    }
  }

  private func refreshVisibleReplyRows() {
    let visibleRows = tableView.rows(in: tableView.visibleRect)
    var changedRows = IndexSet()
    for row in visibleRows.lowerBound..<visibleRows.upperBound {
      guard row < timelineItems.count,
        case .message(_, _, let content) = timelineItems[row],
        content.inReplyTo != nil,
        let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageRowView
      else { continue }

      view.configureReply(details: replyDetails(for: content), onClick: replyClick(for: content))
      changedRows.insert(row)
    }
    if !changedRows.isEmpty {
      tableView.noteHeightOfRows(withIndexesChanged: changedRows)
    }
  }

  @discardableResult
  private func updateHoverOverlay(for rowView: MessageRowView, hovering: Bool, event: NSEvent)
    -> Bool
  {
    if !hovering {
      if hoveredMessageView === rowView {
        let mousePoint = hoverOverlay.convert(event.locationInWindow, from: nil)
        if hoverOverlay.bounds.contains(mousePoint) {
          return true
        }
        hideHoverOverlay()
      }
      return false
    }

    // Tracking areas can enter a row even while the overlay covers it.
    let overlayPoint = hoverOverlay.convert(event.locationInWindow, from: nil)
    if !hoverOverlay.isHidden && hoverOverlay.bounds.contains(overlayPoint) {
      return false
    }

    let rowPoint = tableView.convert(
      NSPoint(x: rowView.bounds.midX, y: rowView.bounds.midY), from: rowView)
    let row = tableView.row(at: rowPoint)
    guard row >= 0, row < timelineItems.count,
      case .message(_, let event, _) = timelineItems[row]
    else { return false }
    hoverOverlay.configure(canReply: event.canBeRepliedTo)
    if hoveredMessageView !== rowView {
      hoveredMessageView?.setHoverHighlight(false)
    }
    hoveredMessageView = rowView
    hoveredMessageId = timelineItems[row].id
    hoveredRowIndex = row
    hoverOverlay.isHidden = false
    positionHoverOverlay()
    return true
  }

  private func positionHoverOverlay() {
    guard !hoverOverlay.isHidden else { return }
    guard let row = hoveredRowIndex,
      let hoveredMessageId,
      row < timelineItems.count,
      timelineItems[row].id == hoveredMessageId,
      let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageRowView
    else {
      hideHoverOverlay()
      return
    }

    if hoveredMessageView !== rowView {
      hoveredMessageView?.setHoverHighlight(false)
      hoveredMessageView = rowView
    }
    rowView.setHoverHighlight(true)

    let rowRect = tableView.convert(tableView.rect(ofRow: row), to: scrollView.contentView)
    let origin = NSPoint(x: rowRect.maxX - hoverOverlay.frame.width - 20, y: rowRect.maxY)
    if hoverOverlay.frame.origin != origin {
      hoverOverlay.setFrameOrigin(origin)
    }
  }

  private func hoverOverlayDidExit(with event: NSEvent) {
    let tablePoint = tableView.convert(event.locationInWindow, from: nil)
    let row = tableView.row(at: tablePoint)
    if row >= 0,
      let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageRowView
    {
      if rowView !== hoveredMessageView {
        rowView.setHoverHighlight(updateHoverOverlay(for: rowView, hovering: true, event: event))
      } else {
        rowView.setHoverHighlight(true)
      }
      return
    }
    hideHoverOverlay()
  }

  private func hideHoverOverlay() {
    hoveredMessageView?.setHoverHighlight(false)
    hoveredMessageView = nil
    hoveredMessageId = nil
    hoveredRowIndex = nil
    hoverOverlay.isHidden = true
  }

  private func toggleReaction(_ key: String, for event: MatrixRustSDK.EventTimelineItem) {
    Task {
      do {
        _ = try await timeline.timeline?.toggleReaction(
          itemId: event.eventOrTransactionId, key: key)
      } catch {
        Logger.timelineTableView.error("Failed to toggle reaction: \(error)")
      }
    }
  }

  private func performHoverAction(_ action: MessageHoverOverlayView.Action) {
    guard let hoveredMessageView else { return }
    let rowPoint = tableView.convert(
      NSPoint(x: hoveredMessageView.bounds.midX, y: hoveredMessageView.bounds.midY),
      from: hoveredMessageView
    )
    let row = tableView.row(at: rowPoint)
    guard row >= 0, row < timelineItems.count,
      case .message(_, let event, _) = timelineItems[row]
    else { return }

    switch action {
    case .reaction(let key):
      toggleReaction(key, for: event)
    case .reactionPicker:
      break  // The old picker button does not have an action yet.
    case .reply:
      timeline.sendReplyTo = event
    case .replyInThread:
      coordinator.windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
    case .pin:
      guard case .eventId(eventId: let eventId) = event.eventOrTransactionId else { return }
      Task {
        do {
          _ = try await timeline.timeline?.pinEvent(eventId: eventId)
        } catch {
          Logger.timelineTableView.error("Failed to pin message: \(error)")
        }
      }
    }
  }

  private var typingNames: [String] {
    let members = timeline.room.members
    return timeline.room.typingUserIds.map { userId in
      members.first(where: { $0.userId == userId })?.displayName ?? userId
    }
  }

  private func listenForTypingUsers() {
    withObservationTracking {
      _ = timeline.room.typingUserIds
      _ = timeline.room.members
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.listenForTypingUsers()
        guard self.tableView.numberOfRows > 0,
          let view = self.tableView.view(atColumn: 0, row: 0, makeIfNecessary: false)
            as? TypingIndicatorRowView
        else { return }
        view.configure(names: self.typingNames)
      }
    }
  }

  @objc func handleTableResize(_ notification: Notification) {
    if oldWidth != tableView.frame.width {
      oldWidth = tableView.frame.width

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false

        let visibleRect = tableView.visibleRect
        let visibleRows = tableView.rows(in: visibleRect)
        tableView.noteHeightOfRows(
          withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound..<visibleRows.upperBound))
      }
    }
  }

  var timelineFetchTask: Task<Void, Never>?

  @objc func viewDidScroll(_ notification: Notification) {
    let currentOffset = scrollView.contentView.bounds.origin.y
    let timelineHeight = scrollView.contentView.documentRect.height
    let viewHeight = scrollView.contentView.documentVisibleRect.height

    let distanceFromTop = timelineHeight - viewHeight - currentOffset
    let threshold: CGFloat = 200.0  // Pixels from the top to trigger load

    if distanceFromTop <= threshold, timelineFetchTask == nil {
      Logger.timelineTableView.info("Fetching older messages (scroll near top)")
      timelineFetchTask = Task {
        await timeline.fetchOlderMessages()
        timelineFetchTask = nil
      }
    }
  }

  func focusTimelineEvent(id eventId: MatrixRustSDK.EventOrTransactionId) {
    guard
      let rowIndex = timelineItems.firstIndex(where: { item in
        switch item {
        case .message(item: _, let event, content: _):
          return event.eventOrTransactionId == eventId
        default:
          return false
        }
      })
    else { return }

    tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    updateSelectedMessage()
    tableView.animateRowToVisible(rowIndex)
  }

  private func updateSelectedMessage() {
    let selectedRow = tableView.selectedRow

    let visibleRows = tableView.rows(in: tableView.visibleRect)
    for row in visibleRows.lowerBound..<visibleRows.upperBound {
      (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageRowView)?
        .setSelected(row == selectedRow)
    }
  }

  private func selectMessageRow(for rowView: MessageRowView) {
    let point = tableView.convert(
      NSPoint(x: rowView.bounds.midX, y: rowView.bounds.midY), from: rowView)
    let row = tableView.row(at: point)
    guard timelineItems.indices.contains(row), case .message = timelineItems[row] else { return }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    updateSelectedMessage()
  }

  private func moveSelection(_ direction: TimelineSelectionDirection) {
    let step = direction.rowStep
    let visibleRows = tableView.rows(in: tableView.visibleRect)
    var row = tableView.selectedRow
    if row < 0 {
      row = direction == .up ? visibleRows.lowerBound - 1 : visibleRows.upperBound
    }

    row += step
    while timelineItems.indices.contains(row) {
      if case .message = timelineItems[row] {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateSelectedMessage()
        tableView.animateRowToVisible(row)
        tableView.window?.makeFirstResponder(tableView)
        return
      }
      row += step
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not available")
  }

  enum TimelineSection {
    case main
    // case typingIndicator
  }

  func timelineDidApply(diffs: [TimelineDiff]) {
    let change = projection.apply(diffs)
    assert(
      projection.sourceItems.map { $0.uniqueId().id }
        == timeline.timelineItems.map { $0.uniqueId().id })
    applyProjectedRows(oldIDs: change.oldIDs, changedIDs: change.changedIDs)
  }

  private func applyProjectedRows(oldIDs: [String], changedIDs: Set<String>) {
    let selectedId =
      oldIDs.indices.contains(tableView.selectedRow) ? oldIDs[tableView.selectedRow] : nil
    let newIDs = timelineItems.map(\.id)
    let structureChanged = oldIDs != newIDs

    if structureChanged {
      var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
      snapshot.appendSections([.main])
      snapshot.appendItems(newIDs.map { TimelineUniqueId(id: $0) }, toSection: .main)
      updatingTimelineItems = true
      dataSource?.apply(snapshot, animatingDifferences: false)
      if let selectedId, let row = newIDs.firstIndex(of: selectedId) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      } else {
        tableView.deselectAll(nil)
      }
      updatingTimelineItems = false
    }

    let oldIDSet = Set(oldIDs)
    var changedRows = IndexSet()
    for (row, id) in newIDs.enumerated() where changedIDs.contains(id) && oldIDSet.contains(id) {
      changedRows.insert(row)
    }
    if !changedRows.isEmpty {
      tableView.noteHeightOfRows(withIndexesChanged: changedRows)
      tableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0))
    }

    if let hoveredMessageId {
      hoveredRowIndex = newIDs.firstIndex(of: hoveredMessageId)
      if hoveredRowIndex == nil {
        hideHoverOverlay()
      } else {
        positionHoverOverlay()
      }
    }
    updateSelectedMessage()
  }

  // values used to track width changes
  var oldWidth: CGFloat?
  private var measurementMessageViews: [MessageContentKind: MessageRowView] = [:]

  private func measurementView(for kind: MessageContentKind) -> MessageRowView {
    if let view = measurementMessageViews[kind] {
      return view
    }
    let view = kind.makeRowView()
    measurementMessageViews[kind] = view
    return view
  }
}

extension TimelineViewController: NSTableViewDelegate {
  func selectionShouldChange(in tableView: NSTableView) -> Bool {
    return true
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    guard timelineItems.indices.contains(row) else { return false }
    if case .message = timelineItems[row] {
      return true
    }
    return false
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !updatingTimelineItems else { return }
    updateSelectedMessage()
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    let item = timelineItems[row]

    if case .profile = item {
      return MessageProfileRowView.rowHeight
    }

    if case .typingIndicator = item {
      return TypingIndicatorRowView.rowHeight
    }

    if case .virtual = item {
      return VirtualItemRowView.rowHeight
    }

    if case .state(_, let event) = item {
      return StateEventRowView.height(for: event, width: tableView.tableColumns[0].width)
    }

    if case .message(_, let event, let content) = item {
      let kind = MessageContentKind(content: content)
      return measurementView(for: kind).height(
        for: content,
        width: tableView.tableColumns[0].width,
        replyDetails: replyDetails(for: content),
        receiptCount: event.readReceipts.count
      )
    }

    preconditionFailure("Unsupported timeline row")
  }
}

class BottomStickyTableView: NSTableView {
  var onLayout: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  override func keyDown(with event: NSEvent) {
    if let direction = TimelineSelectionDirection(event: event) {
      onArrowKey?(direction)
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard row(at: convert(event.locationInWindow, from: nil)) >= 0 else { return }
    super.mouseDown(with: event)
  }

  override func layout() {
    super.layout()
    onLayout?()
  }

  // By returning false, the table starts drawing from the bottom up
  override var isFlipped: Bool {
    return false
  }
}

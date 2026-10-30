import AppKit
import MatrixIntegration
import MatrixProtocols
import MatrixRustSDK
import OSLog
import QuickLookUI
import Utils

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
    self == .up ? -1 : 1
  }
}

enum TimelineItemRowInfo {
  struct StateEntry {
    let item: TimelineItem
    let event: MatrixRustSDK.EventTimelineItem
  }

  case profile(item: TimelineItem, event: MatrixRustSDK.EventTimelineItem)
  case message(
    item: TimelineItem, event: MatrixRustSDK.EventTimelineItem,
    content: MatrixRustSDK.MsgLikeContent)
  /// Entries are nonempty and ordered oldest to newest.
  case state(items: [StateEntry])
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

  var timelineItem: TimelineItem? {
    switch self {
    case .message(let item, _, _):
      item
    case .profile(let item, _):
      item
    case .state(let items):
      items.first?.item
    case .virtual(let item, _):
      item
    case .typingIndicator:
      nil
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
    case .state(let items):
      "state:\(items[0].event.eventOrTransactionId.id)"
    case .virtual(let item, _):
      "virtual:\(item.uniqueId().id)"
    case .typingIndicator:
      "typing-indicator"
    }
  }
}

class TimelineViewController: NSViewController, LiveTimelineFocusDelegate, LiveTimelineDiffDelegate
{
  let appState: AppState
  let windowState: WindowState
  private var actionTasks: [UUID: Task<Void, Never>] = [:]

  private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

  let scrollView = NSScrollView()
  let tableView = TimelineTableView()
  private lazy var documentView = TimelineDocumentView(tableView: tableView)
  private var positionedInitially = false
  private let hoverOverlay = MessageHoverOverlayView()
  private weak var hoveredMessageView: MessageRowView?
  private var hoveredMessageId: String?
  private var hoveredRowIndex: Int?
  private var messageEdit: MessageEditState?
  private var updatingTimelineItems = false
  private var appliedFontSize = TimelineTypography.fontSize

  private struct ReadingAnchor {
    let id: String
    let offset: CGFloat
    let stateEventIDs: [String]?
  }

  private var expandedStateRowIDs = Set<String>()
  private var previewURL: URL?
  private var previewEventIdentifier: String?
  // Keep SDK temporary media alive independently of the reusable row that loaded it.
  private var previewFileHandle: MediaFileHandle?

  let timeline: LiveTimeline
  let composer: ChatComposerState
  private var projection: TimelineRowProjection
  var timelineItems: [TimelineItemRowInfo] {
    projection.rows
  }

  init(
    appState: AppState, windowState: WindowState, timeline: LiveTimeline,
    composer: ChatComposerState
  ) {
    self.appState = appState
    self.windowState = windowState
    self.timeline = timeline
    self.composer = composer
    self.projection = TimelineRowProjection(items: timeline.timelineItems)
    super.init(nibName: nil, bundle: nil)
  }

  func tearDown() {
    NotificationCenter.default.removeObserver(self)

    if timeline.focusDelegate === self {
      timeline.focusDelegate = nil
    }

    if timeline.diffDelegate === self {
      timeline.diffDelegate = nil
    }

    timelineFetchTask?.cancel()
    timelineFetchTask = nil

    for task in actionTasks.values {
      task.cancel()
    }
    actionTasks.removeAll()
  }

  private func startActionTask(_ operation: @escaping @MainActor () async -> Void) {
    let id = UUID()
    actionTasks[id] = Task { @MainActor [weak self] in
      defer { self?.actionTasks[id] = nil }
      guard !Task.isCancelled else { return }
      await operation()
    }
  }

  override func loadView() {
    view = scrollView
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
    tableView.focusRingType = .none

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
            imageLoader: appState.matrixClient,
            focusUser: { [weak self] in
              self?.windowState.focusUser(userId: $0)
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
      case .state(let items):
        let view =
          tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? StateEventRowView ?? StateEventRowView()
        configureStateRow(view, items: items, id: item.id)
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
        view.onMediaPreviewRequest = { [weak self] in
          self?.closeActiveMediaPreview(eventIdentifier: event.eventOrTransactionId.id) ?? false
        }
        view.onMediaPreview = { [weak self, weak view] url, handle in
          guard let self, let view, view.window === self.view.window else { return }
          self.selectMessageRow(for: view)
          self.showMediaPreview(
            url: url, handle: handle, eventIdentifier: event.eventOrTransactionId.id)
        }
        view.configureEditing(messageEdit?.id == event.eventOrTransactionId ? messageEdit : nil)
        view.configure(
          event: event,
          content: content,
          replyDetails: self.replyDetails(for: content),
          onReplyClick: self.replyClick(for: content),
          onThreadClick: { [weak self] in
            self?.windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
          },
          ownUserId: try? self.appState.matrixClient?.client.userId(),
          onReactionClick: { [weak self] key in
            self?.toggleReaction(key, for: event)
          },
          roomMembers: self.timeline.room.members,
          matrixClient: self.appState.matrixClient,
          handleMatrixUri: { [weak self] matrixUri in
            guard let self else { return false }
            self.handleMatrixUri(matrixUri)
            return true
          }
        )
        view.setSelected(tableView.selectedRow == row)
        view.identifier = kind.reuseIdentifier
        return view
      }
    }

    tableView.delegate = self

    scrollView.documentView = documentView
    scrollView.verticalScrollElasticity = .allowed
    hoverOverlay.isHidden = true
    hoverOverlay.onMouseExited = { [weak self] event in
      self?.hoverOverlayDidExit(with: event)
    }
    hoverOverlay.onAction = { [weak self] action in
      self?.performHoverAction(action)
    }
    scrollView.contentView.addSubview(hoverOverlay, positioned: .above, relativeTo: documentView)
    scrollView.hasVerticalScroller = true

    scrollView.automaticallyAdjustsContentInsets = true

    scrollView.drawsBackground = false
    tableView.backgroundColor = .clear

    // Subscribe to view resize notifications
    scrollView.contentView.postsBoundsChangedNotifications = true
    scrollView.contentView.postsFrameChangedNotifications = true
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

  override func viewDidLayout() {
    super.viewDidLayout()
    documentView.updateGeometry()
    guard !positionedInitially, scrollView.contentView.bounds.height > 0 else { return }
    positionedInitially = true
    tableView.layoutSubtreeIfNeeded()
    tableView.scrollToBottom()
  }

  func updateFontSize(_ fontSize: Int) {
    guard appliedFontSize != CGFloat(fontSize) else { return }
    appliedFontSize = CGFloat(fontSize)
    guard isViewLoaded else { return }

    let clipView = scrollView.contentView
    let followBottom = documentView.isAtBottom
    let candidates = readingAnchorCandidates()
    let oldOrigin = clipView.bounds.origin
    let wasUpdating = updatingTimelineItems
    updatingTimelineItems = true
    defer { updatingTimelineItems = wasUpdating }

    hideHoverOverlay()
    measurementMessageViews.removeAll()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      let rows = IndexSet(integersIn: 0..<tableView.numberOfRows)
      tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
      tableView.noteHeightOfRows(withIndexesChanged: rows)
      updateSelectedMessage()
      scrollView.layoutSubtreeIfNeeded()
      documentView.updateGeometry()

      var bounds = clipView.bounds
      bounds.origin = oldOrigin
      if followBottom {
        bounds.origin.y = documentView.bottomAlignedOriginY
      } else if let (anchor, row) = survivingReadingAnchor(from: candidates) {
        let rect = tableView.rect(ofRow: row)
        let top = clipView.convert(NSPoint(x: rect.minX, y: rect.minY), from: tableView)
        bounds.origin.y = top.y - anchor.offset
      }
      clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
      scrollView.reflectScrolledClipView(clipView)
    }
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
      guard let self else { return }
      self.timeline.focusEvent(id: .eventId(eventId: replyId))
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
      tableView.withBottomFollowing {
        tableView.noteHeightOfRows(withIndexesChanged: changedRows)
      }
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
    hoverOverlay.configure(
      canReply: event.canBeRepliedTo,
      canEdit: event.isOwn && event.isEditable && editableText(for: event) != nil)
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

    let clipView = scrollView.contentView
    let rowRect = tableView.convert(tableView.rect(ofRow: row), to: clipView)
    let top = clipView.isFlipped ? rowRect.minY - hoverOverlay.frame.height : rowRect.maxY
    let origin = NSPoint(x: rowRect.maxX - hoverOverlay.frame.width - 20, y: top)
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
    startActionTask { [weak self] in
      do {
        _ = try await self?.timeline.timeline?
          .toggleReaction(itemId: event.eventOrTransactionId, key: key)
      } catch {
        guard !Task.isCancelled else { return }
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
    case .edit:
      beginEditing(event: event)
    case .reply:
      composer.beginReply(to: event)
    case .replyInThread:
      windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
    case .pin:
      guard case .eventId(eventId: let eventId) = event.eventOrTransactionId else { return }
      startActionTask { [weak self] in
        do {
          _ = try await self?.timeline.timeline?.pinEvent(eventId: eventId)
        } catch {
          guard !Task.isCancelled else { return }
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
          let view = self.tableView.view(
            atColumn: 0, row: self.tableView.numberOfRows - 1, makeIfNecessary: false)
            as? TypingIndicatorRowView
        else { return }
        view.configure(names: self.typingNames)
      }
    }
  }

  private func configureStateRow(
    _ view: StateEventRowView, items: [TimelineItemRowInfo.StateEntry], id: String
  ) {
    view.configure(
      items: items, expanded: expandedStateRowIDs.contains(id),
      handleMatrixUri: { [weak self] matrixUri in
        guard let self else { return false }
        self.handleMatrixUri(matrixUri)
        return true
      }
    ) { [weak self] in
      self?.toggleStateRow(id: id)
    }
  }

  private func handleMatrixUri(_ matrixUri: MatrixUriScheme) {
    if case .user(let userID) = matrixUri.kind, matrixUri.action == nil {
      self.windowState.focusUser(userId: userID)
      return
    }
    self.windowState.selectedScreen = .loadMatrixUrl(matrixUri)
  }

  private func toggleStateRow(id: String) {
    guard
      let row = timelineItems.firstIndex(where: { $0.id == id }),
      case .state(let items) = timelineItems[row], items.count > 1
    else { return }

    if !expandedStateRowIDs.insert(id).inserted {
      expandedStateRowIDs.remove(id)
    }

    if let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
      as? StateEventRowView
    {
      configureStateRow(view, items: items, id: id)
    }

    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
    positionHoverOverlay()
  }

  @objc func handleTableResize(_ notification: Notification) {
    if oldWidth != tableView.frame.width {
      oldWidth = tableView.frame.width

      documentView.updateGeometry()

      tableView.withBottomFollowing {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        tableView.noteHeightOfRows(
          withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound..<visibleRows.upperBound))
      }
    }
  }

  var timelineFetchTask: Task<Void, Never>?

  @objc func viewDidScroll(_ notification: Notification) {
    guard positionedInitially, !updatingTimelineItems else { return }
    let distanceFromTop = tableView.visibleRect.minY - tableView.bounds.minY
    let threshold: CGFloat = 200.0  // Pixels from the top to trigger load

    if distanceFromTop <= threshold, timelineFetchTask == nil {
      Logger.timelineTableView.info("Fetching older messages (scroll near top)")
      timelineFetchTask = Task { [weak self] in
        await self?.timeline.fetchOlderMessages()
        self?.timelineFetchTask = nil
      }
    }
  }

  func rowForEventId(id eventId: MatrixRustSDK.EventOrTransactionId) -> Int? {
    timelineItems.firstIndex { item in
      switch item {
      case .message(item: _, let event, content: _):
        return event.eventOrTransactionId == eventId
      default:
        return false
      }
    }
  }

  func focusTimelineEvent(id eventId: MatrixRustSDK.EventOrTransactionId) {
    guard let rowIndex = rowForEventId(id: eventId) else { return }

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
      row = direction == .up ? visibleRows.upperBound : visibleRows.lowerBound - 1
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

  private func readingAnchorCandidates() -> [ReadingAnchor] {
    let clipView = scrollView.contentView
    guard !documentView.isAtBottom else { return [] }
    let visibleRows = tableView.rows(in: tableView.visibleRect)
    guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return [] }

    var messages: [ReadingAnchor] = []
    var states: [ReadingAnchor] = []
    for row in visibleRows.location..<min(NSMaxRange(visibleRows), timelineItems.count) {
      let item = timelineItems[row]
      let stateEventIDs: [String]?
      switch item {
      case .message:
        stateEventIDs = nil
      case .state(let items):
        stateEventIDs = items.map { $0.event.eventOrTransactionId.id }
      case .profile, .virtual, .typingIndicator:
        continue
      }
      let rect = tableView.rect(ofRow: row)
      let top = clipView.convert(NSPoint(x: rect.minX, y: rect.minY), from: tableView)
      let anchor = ReadingAnchor(
        id: item.id, offset: top.y - clipView.bounds.minY,
        stateEventIDs: stateEventIDs)
      if stateEventIDs == nil {
        messages.append(anchor)
      } else {
        states.append(anchor)
      }
    }
    // Structural rows can stay at the top while the messages below them move.
    // Prefer message content, with unchanged state groups as a fallback.
    return messages + states
  }

  private func survivingReadingAnchor(from candidates: [ReadingAnchor])
    -> (anchor: ReadingAnchor, row: Int)?
  {
    guard !candidates.isEmpty else { return nil }
    let candidateIDs = Set(candidates.map(\.id))
    var rowsByID: [String: Int] = [:]
    for (row, item) in timelineItems.enumerated() where candidateIDs.contains(item.id) {
      rowsByID[item.id] = row
    }
    for candidate in candidates {
      guard let row = rowsByID[candidate.id] else { continue }
      if let expectedIDs = candidate.stateEventIDs {
        guard case .state(let items) = timelineItems[row],
          items.map({ $0.event.eventOrTransactionId.id }) == expectedIDs
        else { continue }
      }
      return (candidate, row)
    }
    return nil
  }

  func timelineDidApply(diffs: [TimelineDiff]) {
    let clipView = scrollView.contentView
    let followBottom = documentView.isAtBottom
    let oldOrigin = clipView.bounds.origin
    let candidates = readingAnchorCandidates()

    // Layout and scroll restoration may send bounds notifications. Do not fetch
    // more history based on an intermediate viewport position.
    updatingTimelineItems = true
    defer { updatingTimelineItems = false }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false

      let change = projection.apply(diffs)

      assert(
        projection.sourceItems.map { $0.uniqueId().id }
          == timeline.timelineItems.map { $0.uniqueId().id }
      )

      applyProjectedRows(oldIDs: change.oldIDs, changedIDs: change.changedIDs)

      // Settle the entire scroll-view hierarchy before measuring the anchor and
      // restoring the viewport. No further layout or scroll adjustment follows.
      scrollView.layoutSubtreeIfNeeded()
      documentView.updateGeometry()

      var bounds = clipView.bounds
      bounds.origin = oldOrigin
      if followBottom {
        bounds.origin.y = documentView.bottomAlignedOriginY
      } else if let (anchor, row) = survivingReadingAnchor(from: candidates) {
        let rect = tableView.rect(ofRow: row)
        let top = clipView.convert(NSPoint(x: rect.minX, y: rect.minY), from: tableView)
        bounds.origin.y = top.y - anchor.offset
      }
      clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
      scrollView.reflectScrolledClipView(clipView)
    }
    positionHoverOverlay()
  }

  private func applyProjectedRows(oldIDs: [String], changedIDs: Set<String>) {
    let wasUpdating = updatingTimelineItems
    updatingTimelineItems = true
    defer { updatingTimelineItems = wasUpdating }
    let selectedId =
      oldIDs.indices.contains(tableView.selectedRow) ? oldIDs[tableView.selectedRow] : nil
    let newIDs = timelineItems.map(\.id)
    expandedStateRowIDs.formIntersection(newIDs)
    let structureChanged = oldIDs != newIDs

    if structureChanged {
      var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
      snapshot.appendSections([.main])
      snapshot.appendItems(newIDs.map { TimelineUniqueId(id: $0) }, toSection: .main)
      dataSource?.apply(snapshot, animatingDifferences: false)
      if let selectedId, let row = newIDs.firstIndex(of: selectedId) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      } else {
        tableView.deselectAll(nil)
      }
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

extension TimelineViewController: @preconcurrency QLPreviewPanelDataSource {
  private func closeActiveMediaPreview(eventIdentifier: String) -> Bool {
    guard previewEventIdentifier == eventIdentifier,
      QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.isVisible, panel.currentController as AnyObject? === self,
      let previewURL, panel.currentPreviewItem?.previewItemURL == previewURL
    else { return false }

    panel.close()
    return true
  }

  private func showMediaPreview(url: URL, handle: MediaFileHandle, eventIdentifier: String) {
    guard let window = view.window, let panel = QLPreviewPanel.shared() else { return }
    previewFileHandle = handle
    previewURL = url
    previewEventIdentifier = eventIdentifier

    // Use the existing view/controller responder chain, bypassing text selection
    // responders in captions and the composer that can otherwise claim Quick Look.
    guard window.makeFirstResponder(tableView) else { return }
    panel.updateController()
    panel.makeKeyAndOrderFront(nil)
    if panel.currentController as AnyObject? === self {
      panel.reloadData()
      panel.currentPreviewItemIndex = 0
    } else {
      Logger.viewCycle.error("Timeline could not obtain Quick Look panel control")
    }
  }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { previewURL != nil }
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      panel.dataSource = self
      panel.reloadData()
      panel.currentPreviewItemIndex = 0
    }
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      if panel.dataSource === self {
        panel.dataSource = nil
      }
    }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    previewURL == nil ? 0 : 1
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    guard index == 0 else { return nil }
    return previewURL as NSURL?
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

    if case .state(let items) = item {
      return StateEventRowView.height(
        for: items, width: tableView.tableColumns[0].width,
        expanded: expandedStateRowIDs.contains(item.id))
    }

    if case .message(_, let event, let content) = item {
      let kind = MessageContentKind(content: content)
      let measurement = measurementView(for: kind)
      measurement.configureEditing(
        messageEdit?.id == event.eventOrTransactionId ? messageEdit : nil)
      return measurement.height(
        for: content,
        width: tableView.tableColumns[0].width,
        replyDetails: replyDetails(for: content),
        reactions: event.reactions,
        receiptCount: event.readReceipts.count
      )
    }

    preconditionFailure("Unsupported timeline row")
  }
}

// Message editing
extension TimelineViewController {
  private func editableText(for event: MatrixRustSDK.EventTimelineItem) -> String? {
    guard case .msgLike(let content) = event.content,
      case .message(let message) = content.kind
    else { return nil }
    switch message.msgType {
    case .text(let text): return text.body
    case .notice(let notice): return notice.body
    case .emote(let emote): return emote.body
    case .image(let image): return image.caption ?? ""
    case .video(let video): return video.caption ?? ""
    case .file(let file): return file.caption ?? ""
    case .gallery(let gallery): return gallery.body
    default: return nil
    }
  }

  private func beginEditing(event: MatrixRustSDK.EventTimelineItem) {
    guard event.isOwn, event.isEditable, let text = editableText(for: event) else { return }
    if messageEdit?.id == event.eventOrTransactionId { return }

    var dirtyEvents = Set<MatrixRustSDK.EventOrTransactionId>([event.eventOrTransactionId])
    if let messageEdit {
      dirtyEvents.insert(messageEdit.id)
    }

    let state = MessageEditState(id: event.eventOrTransactionId, text: text)
    state.mentionCandidateProvider = { [weak room = timeline.room] in room?.members ?? [] }
    state.imageLoader = appState.matrixClient
    state.onChange = { [weak self, weak state] in
      guard let self, let state, self.messageEdit === state,
        let row = self.rowForEventId(id: state.id)
      else { return }
      self.tableView.withBottomFollowing {
        self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
      }
    }
    state.onCancel = { [weak self, weak state] in
      guard let self, let state, self.messageEdit === state else { return }
      self.messageEdit = nil
      self.refreshEditingRows(events: [event.eventOrTransactionId])
    }
    state.onSave = { [weak self, weak state] in
      guard let self, let state else { return }
      self.saveEdit(state, event: event)
    }
    messageEdit = state
    hideHoverOverlay()

    refreshEditingRows(events: dirtyEvents)
  }

  private func refreshEditingRows(events: Set<MatrixRustSDK.EventOrTransactionId>) {
    var rows = IndexSet()
    for eventId in events {
      guard
        let row = rowForEventId(id: eventId),
        let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
          as? MessageRowView
      else { continue }

      view.configureEditing(messageEdit?.id == eventId ? messageEdit : nil)
      rows.insert(row)
    }
    tableView.withBottomFollowing {
      tableView.noteHeightOfRows(withIndexesChanged: rows)
    }
  }

  private func saveEdit(_ state: MessageEditState, event: MatrixRustSDK.EventTimelineItem) {
    guard messageEdit === state, !state.isSaving, let sdkTimeline = timeline.timeline,
      case .msgLike(let content) = event.content,
      case .message(let message) = content.kind
    else { return }

    let editedContent: EditedContent

    switch message.msgType {
    case .text:
      editedContent = .roomMessage(content: messageEventContentFromMarkdown(md: state.text))
    case .emote:
      editedContent = .roomMessage(content: messageEventContentFromMarkdownAsEmote(md: state.text))
    case .notice(var notice):
      notice.body = state.text
      notice.formatted = nil
      do {
        editedContent = .roomMessage(
          content: try messageEventContentNew(msgtype: .notice(content: notice))
        )
      } catch {
        state.error = error.localizedDescription
        refreshEditingRows(events: [event.eventOrTransactionId])
        return
      }
    default:
      editedContent = .mediaCaption(
        caption: state.text.isEmpty ? nil : state.text,
        formattedCaption: nil, mentions: nil)
    }
    state.isSaving = true
    state.error = nil
    refreshEditingRows(events: [event.eventOrTransactionId])
    startActionTask { [weak self] in
      do {
        try await sdkTimeline.edit(
          eventOrTransactionId: event.eventOrTransactionId, newContent: editedContent)
        guard let self, self.messageEdit === state else { return }
        self.messageEdit = nil
        self.refreshEditingRows(events: [event.eventOrTransactionId])
      } catch {
        guard let self, self.messageEdit === state else { return }
        state.isSaving = false
        state.error = error.localizedDescription
        self.refreshEditingRows(events: [event.eventOrTransactionId])
      }
    }
  }
}

/// A conventional top-down table. Only passive updates opt into bottom-following;
/// user-driven row expansion deliberately leaves the scroll offset alone.
class TimelineTableView: NSTableView {
  var onLayout: (() -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?

  func withBottomFollowing(_ update: () -> Void) {
    let followBottom =
      (superview as? TimelineDocumentView)?.isAtBottom ?? false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      update()
      layoutSubtreeIfNeeded()
      (superview as? TimelineDocumentView)?.updateGeometry()
      if followBottom {
        scrollToBottom()
      } else if let clipView = enclosingScrollView?.contentView {
        clipView.scroll(to: clipView.constrainBoundsRect(clipView.bounds).origin)
      }
    }
  }

  func scrollToBottom() {
    guard let scrollView = enclosingScrollView else { return }
    let clipView = scrollView.contentView
    let documentView = superview as? TimelineDocumentView
    documentView?.updateGeometry()
    var bounds = clipView.bounds
    bounds.origin.y = documentView?.bottomAlignedOriginY ?? (frame.maxY - bounds.height)
    clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
    scrollView.reflectScrolledClipView(clipView)
  }

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

  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()

    // Visible row heights are refreshed live while resizing the window.
    // The remaining rows are only resized once when live resize ends to stay performant.
    let visibleRows = rows(in: visibleRect)
    let allRows = IndexSet(integersIn: 0..<numberOfRows)
    guard let scrollView = enclosingScrollView,
      visibleRows.location != NSNotFound, visibleRows.length > 0
    else {
      noteHeightOfRows(withIndexesChanged: allRows)
      return
    }
    let otherRows = allRows.subtracting(
      IndexSet(integersIn: visibleRows.lowerBound..<visibleRows.upperBound))
    let clipView = scrollView.contentView
    let anchorRow = visibleRows.location
    let anchorRect = rect(ofRow: anchorRow)
    let anchorTop = clipView.convert(anchorRect.origin, from: self)
    let anchorOffset = anchorTop.y - clipView.bounds.minY

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      noteHeightOfRows(withIndexesChanged: otherRows)

      // Heights above the viewport move the anchor in document coordinates.
      // Settle geometry before compensating, including the bottom-aligned table origin.
      scrollView.layoutSubtreeIfNeeded()
      (superview as? TimelineDocumentView)?.updateGeometry()
      let newTop = clipView.convert(rect(ofRow: anchorRow).origin, from: self)
      var bounds = clipView.bounds
      bounds.origin.y = newTop.y - anchorOffset
      clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
      scrollView.reflectScrolledClipView(clipView)
    }
  }

  override func layout() {
    super.layout()
    (superview as? TimelineDocumentView)?.updateGeometry()
    onLayout?()
  }
}

/// Keeps unused space above the table while leaving scrolling geometry to AppKit.
final class TimelineDocumentView: NSView {
  private let tableView: TimelineTableView
  private var updatingGeometry = false
  private var previousViewportHeight: CGFloat?
  private var previousBottomInset: CGFloat?

  override var isFlipped: Bool { true }

  init(tableView: TimelineTableView) {
    self.tableView = tableView
    super.init(frame: .zero)
    addSubview(tableView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var bottomAlignedOriginY: CGFloat {
    guard let clipView = enclosingScrollView?.contentView else { return 0 }
    return frame.maxY - clipView.bounds.height + clipView.contentInsets.bottom
  }

  var isAtBottom: Bool {
    guard let clipView = enclosingScrollView?.contentView else { return true }
    return bottomAlignedOriginY - clipView.bounds.minY <= 2
  }

  func updateGeometry() {
    guard !updatingGeometry, let scrollView = enclosingScrollView else { return }
    updatingGeometry = true
    defer { updatingGeometry = false }

    let clipView = scrollView.contentView
    let viewportHeight = clipView.bounds.height
    let insets = clipView.contentInsets
    let resized = previousViewportHeight != nil && previousViewportHeight != viewportHeight
    let bottomInsetChanged = previousBottomInset != nil && previousBottomInset != insets.bottom

    let followBottom =
      (resized || bottomInsetChanged)
      && frame.maxY - (previousViewportHeight ?? viewportHeight)
        + (previousBottomInset ?? insets.bottom) - clipView.bounds.minY <= 2

    previousViewportHeight = viewportHeight
    previousBottomInset = insets.bottom

    let width = max(0, clipView.bounds.width - insets.left - insets.right)
    if tableView.frame.width != width {
      tableView.setFrameSize(NSSize(width: width, height: tableView.frame.height))
    }
    tableView.layoutSubtreeIfNeeded()
    let rowsHeight =
      tableView.numberOfRows > 0
      ? tableView.rect(ofRow: tableView.numberOfRows - 1).maxY : 0
    let height = max(rowsHeight, max(0, viewportHeight - insets.top - insets.bottom))
    let size = NSSize(width: width, height: height)
    if frame.size != size {
      setFrameSize(size)
    }
    let tableFrame = NSRect(x: 0, y: height - rowsHeight, width: width, height: rowsHeight)
    if tableView.frame != tableFrame {
      tableView.frame = tableFrame
    }

    if followBottom {
      var bounds = clipView.bounds
      bounds.origin.y = bottomAlignedOriginY
      clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
    }
    scrollView.reflectScrolledClipView(clipView)
  }
}

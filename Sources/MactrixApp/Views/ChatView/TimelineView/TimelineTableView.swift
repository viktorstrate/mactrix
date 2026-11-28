import AppKit
import ContactLinking
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

  enum PaginationSpinnerPosition {
    case top, bottom
  }

  case profile(item: TimelineItem, event: MatrixRustSDK.EventTimelineItem)
  case message(
    item: TimelineItem, event: MatrixRustSDK.EventTimelineItem,
    content: MatrixRustSDK.MsgLikeContent)
  /// Entries are nonempty and ordered oldest to newest.
  case state(items: [StateEntry])
  case virtual(item: TimelineItem, virtual: MatrixRustSDK.VirtualTimelineItem)
  case typingIndicator
  case paginationSpinner(position: PaginationSpinnerPosition)

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
    case .paginationSpinner:
      return NSUserInterfaceItemIdentifier("pagination-spinner")
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
    case .typingIndicator, .paginationSpinner:
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
    case .paginationSpinner(.bottom):
      "pagination-spinner-bottom"
    case .paginationSpinner(.top):
      "pagination-spinner-top"
    }
  }
}

class TimelineViewController: NSViewController, LiveTimelineFocusDelegate, LiveTimelineDiffDelegate
{
  let windowState: WindowState
  private var actionTasks: [UUID: Task<Void, Never>] = [:]

  private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

  let scrollView = NSScrollView()
  let tableView = TimelineTableView()
  private lazy var documentView = TimelineDocumentView(
    tableView: tableView, allowsBottomFollowing: timeline.focusedEventId == nil)
  private var positionedInitially = false
  private var tornDown = false
  private let hoverOverlay = MessageHoverOverlayView()
  private weak var hoveredMessageView: MessageRowView?
  private var hoveredMessageId: String?
  private var hoveredRowIndex: Int?
  private var reactionPickerPopover: NSPopover?
  private var reactionPickerMessageID: String?
  enum ReactionPickerPresentationSource {
    case hoverButton
    case selectedMessage
  }

  private var reactionPickerSource: ReactionPickerPresentationSource?
  private var isHoverReactionPickerOpen: Bool {
    reactionPickerPopover != nil && reactionPickerSource == .hoverButton
  }
  private var updatingReactionPickerAnchor = false
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
  private var showTopPaginationSpinner = false
  private var showBottomPaginationSpinner = false
  private(set) var timelineItems: [TimelineItemRowInfo] = []

  init(
    windowState: WindowState, timeline: LiveTimeline,
    composer: ChatComposerState
  ) {
    self.windowState = windowState
    self.timeline = timeline
    self.composer = composer
    self.projection = TimelineRowProjection(items: timeline.timelineItems)
    super.init(nibName: nil, bundle: nil)
  }

  func tearDown() {
    closeReactionPicker()
    clearConversationSelection()
    NotificationCenter.default.removeObserver(self)

    if timeline.focusDelegate === self {
      timeline.focusDelegate = nil
    }

    if timeline.diffDelegate === self {
      timeline.diffDelegate = nil
    }

    timelineFetchTask?.cancel()
    timelineFetchTask = nil
    timelineForwardFetchTask?.cancel()
    timelineForwardFetchTask = nil
    tornDown = true

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

  override func viewDidAppear() {
    super.viewDidAppear()
    if windowState.conversationSelection == nil {
      updateConversationSelection(makeActive: true)
    }
  }

  override func viewWillDisappear() {
    closeReactionPicker()
    clearConversationSelection()
    super.viewWillDisappear()
  }

  private func clearConversationSelection() {
    if windowState.conversationSelection?.owner === self {
      windowState.conversationSelection = nil
    }
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
      self?.updateReactionPickerAnchor()
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
            imageLoader: windowState.matrixClient,
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
      case .paginationSpinner:
        let view =
          tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
          as? PaginationSpinnerRowView ?? PaginationSpinnerRowView()
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
        view.onSendStatusClick = { [weak self] anchor in
          self?.showSendStatusMenu(for: event, from: anchor)
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
          ownUserId: try? self.windowState.matrixClient?.client.userId(),
          onReactionClick: { [weak self] key in
            self?.toggleReaction(key, for: event)
          },
          roomMembers: self.timeline.room.members,
          matrixClient: self.windowState.matrixClient,
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
    hoverOverlay.onInteractionClosed = { [weak self] in
      self?.hideHoverOverlay()
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidScroll(_:)),
      name: NSScrollView.didLiveScrollNotification,
      object: scrollView
    )

    timeline.focusDelegate = self
    timeline.diffDelegate = self
    showTopPaginationSpinner = timeline.fetchingOlderMessages
    showBottomPaginationSpinner = timeline.fetchingNewerMessages
    applyProjectedRows(changedIDs: [])
    listenForTypingUsers()
    listenForContactChanges()
    listenForReplyDetails()
    listenForRecentReactions()
    listenForRoomInfo()
    listenForTimelinePagination()
    if let recentReactions = windowState.matrixClient?.recentReactions {
      startActionTask {
        _ = await recentReactions.refresh()
      }
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    documentView.updateGeometry()
    positionInitiallyIfNeeded()
    paginateIfNeeded(onlyIfUnderfilled: true)
  }

  private func positionInitiallyIfNeeded() {
    guard !positionedInitially, !updatingTimelineItems, timeline.isConfigured,
      scrollView.contentView.bounds.height > 0
    else { return }
    let wasUpdating = updatingTimelineItems
    updatingTimelineItems = true
    defer { updatingTimelineItems = wasUpdating }
    if let eventId = timeline.focusedEventId {
      guard let row = rowForEventId(id: .eventId(eventId: eventId)) else { return }
      positionedInitially = true
      tableView.layoutSubtreeIfNeeded()
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      updateSelectedMessage(makeActive: true)
      let clipView = scrollView.contentView
      let rect = tableView.rect(ofRow: row)
      let center = clipView.convert(NSPoint(x: rect.midX, y: rect.midY), from: tableView)
      clipView.scroll(
        to: clipView.constrainBoundsRect(
          NSRect(
            x: clipView.bounds.minX, y: center.y - clipView.bounds.height / 2,
            width: clipView.bounds.width, height: clipView.bounds.height)
        ).origin)
      scrollView.reflectScrolledClipView(clipView)
    } else {
      positionedInitially = true
      tableView.layoutSubtreeIfNeeded()
      tableView.scrollToBottom()
    }
  }

  func updateFontSize(_ fontSize: Int) {
    guard appliedFontSize != CGFloat(fontSize) else { return }
    appliedFontSize = CGFloat(fontSize)
    guard isViewLoaded else { return }

    let clipView = scrollView.contentView
    let followBottom = documentView.shouldFollowBottom
    let candidates = readingAnchorCandidates()
    let oldOrigin = clipView.bounds.origin
    let wasUpdating = updatingTimelineItems
    updatingTimelineItems = true
    defer { updatingTimelineItems = wasUpdating }

    closeReactionPicker()
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
      let target = MatrixRustSDK.EventOrTransactionId.eventId(eventId: replyId)
      if self.rowForEventId(id: target) != nil {
        self.focusTimelineEvent(id: target)
      } else {
        self.windowState.focusReply(eventId: replyId, from: self.timeline)
      }
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

  private func listenForRecentReactions() {
    guard let recentReactions = windowState.matrixClient?.recentReactions else { return }
    let keys = withObservationTracking {
      recentReactions.isActive ? recentReactions.cachedKeys : []
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.listenForRecentReactions()
      }
    }
    hoverOverlay.setQuickReactions(keys)
    positionHoverOverlay()
    updateReactionPickerAnchor()
  }

  private func listenForRoomInfo() {
    withObservationTracking {
      _ = timeline.room.roomInfo
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.listenForRoomInfo()
        self.refreshHoveredMessage()
      }
    }
  }

  private func refreshHoveredMessage() {
    guard let hoveredMessageId else { return }
    guard let row = timelineItems.firstIndex(where: { $0.id == hoveredMessageId }),
      case .message(_, let event, _) = timelineItems[row]
    else {
      hideHoverOverlay()
      return
    }
    hoveredRowIndex = row
    configureHoverOverlay(for: event)
    positionHoverOverlay()
    updateReactionPickerAnchor()
  }

  private func configureHoverOverlay(for event: MatrixRustSDK.EventTimelineItem) {
    hoverOverlay.configure(
      canReply: event.canBeRepliedTo,
      canEdit: event.isOwn && event.isEditable && editableText(for: event) != nil,
      canDelete: canDeleteMessage(event),
      canReact: canPerformMessageAction(.reactionPicker, for: event),
      canPin: canPerformMessageAction(.pin, for: event),
      isPinned: isMessagePinned(event),
      canCopyLink: canPerformMessageAction(.copyMessageLink, for: event),
      canRetrySend: canPerformMessageAction(.retrySend, for: event),
      downloadFilenames: MessageDownloadAttachment.attachments(for: event).map(\.suggestedFilename))
  }

  @discardableResult
  private func updateHoverOverlay(for rowView: MessageRowView, hovering: Bool, event: NSEvent)
    -> Bool
  {
    guard reactionPickerPopover == nil else {
      return isHoverReactionPickerOpen && hoveredMessageView === rowView
    }
    guard !hoverOverlay.isPresentingInteraction else {
      return hoveredMessageView === rowView
    }
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
    configureHoverOverlay(for: event)
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
      if isHoverReactionPickerOpen { closeReactionPicker() }
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
    guard !hoverOverlay.isPresentingInteraction, !isHoverReactionPickerOpen else { return }
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
    guard !hoverOverlay.isPresentingInteraction, !isHoverReactionPickerOpen else { return }
    hoveredMessageView?.setHoverHighlight(false)
    hoveredMessageView = nil
    hoveredMessageId = nil
    hoveredRowIndex = nil
    hoverOverlay.isHidden = true
  }

  private func toggleReaction(_ key: String, for event: MatrixRustSDK.EventTimelineItem) {
    guard let sdkTimeline = timeline.timeline else { return }
    let recents = windowState.matrixClient?.recentReactions
    startActionTask {
      do {
        if let recents {
          try await recents.toggleReaction(key) {
            try await sdkTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
          }
        } else {
          _ = try await sdkTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
        }
      } catch {
        guard !Task.isCancelled else { return }
        Logger.timelineTableView.error("Failed to toggle reaction: \(error)")
      }
    }
  }

  /// Shows what can be done with a message that hasn't been sent, below its send status icon.
  private func showSendStatusMenu(for event: MatrixRustSDK.EventTimelineItem, from anchor: NSView) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (action, title, symbol) in [
      (
        MessageHoverOverlayView.Action.retrySend, String(localized: "Retry Sending"),
        "arrow.clockwise"
      ),
      (.delete, String(localized: "Delete message"), "trash"),
    ] where canPerformMessageAction(action, for: event) {
      let item = NSMenuItem(
        title: title, action: #selector(performSendStatusMenuItem(_:)), keyEquivalent: "")
      item.target = self
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      item.representedObject = PendingMessageAction(action: action, event: event)
      menu.addItem(item)
    }
    guard !menu.items.isEmpty else { return }
    let origin = NSPoint(
      x: anchor.bounds.minX, y: anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4)
    menu.popUp(positioning: nil, at: origin, in: anchor)
  }

  @objc private func performSendStatusMenuItem(_ sender: NSMenuItem) {
    guard let pending = sender.representedObject as? PendingMessageAction else { return }
    performMessageAction(pending.action, for: pending.event)
  }

  private func canDeleteMessage(_ event: MatrixRustSDK.EventTimelineItem) -> Bool {
    guard let powerLevels = timeline.room.roomInfo?.powerLevels else { return false }
    return event.isOwn
      ? powerLevels.canOwnUserRedactOwn()
      : powerLevels.canOwnUserRedactOther()
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

    performMessageAction(action, for: event, reactionPickerSource: .hoverButton)
  }

  func isMessagePinned(_ event: MatrixRustSDK.EventTimelineItem) -> Bool {
    guard case .eventId(let eventID) = event.eventOrTransactionId else { return false }
    return timeline.room.roomInfo?.pinnedEventIds.contains(eventID) == true
  }

  func canPerformMessageAction(
    _ action: MessageHoverOverlayView.Action, for event: MatrixRustSDK.EventTimelineItem
  ) -> Bool {
    switch action {
    case .reaction, .reactionPicker:
      return timeline.timeline != nil && event.isRemote
        && timeline.room.roomInfo?.powerLevels?.canOwnUserSendMessage(message: .reaction) == true
    case .reply, .replyInThread:
      return event.canBeRepliedTo
    case .edit:
      return event.isOwn && event.isEditable && editableText(for: event) != nil
    case .pin:
      guard case .eventId = event.eventOrTransactionId else { return false }
      return timeline.timeline != nil
        && timeline.room.roomInfo?.powerLevels?.canOwnUserPinUnpin() == true
    case .delete:
      return timeline.timeline != nil && canDeleteMessage(event)
    case .retrySend:
      guard case .sendingFailed = event.localSendState else { return false }
      return event.lazyProvider.getSendHandle() != nil
    case .copyMessageLink:
      if case .eventId = event.eventOrTransactionId { return true }
      return false
    case .showSource:
      return true
    case .downloadToFile(let index):
      return windowState.matrixClient != nil
        && MessageDownloadAttachment.attachments(for: event).indices.contains(index)
    }
  }

  func performMessageAction(
    _ action: MessageHoverOverlayView.Action, for event: MatrixRustSDK.EventTimelineItem,
    reactionPickerSource: ReactionPickerPresentationSource = .selectedMessage
  ) {
    guard canPerformMessageAction(action, for: event) else { return }
    switch action {
    case .reaction(let key):
      toggleReaction(key, for: event)
    case .reactionPicker:
      do {
        try showReactionPicker(for: event, source: reactionPickerSource)
      } catch {
        Logger.timelineTableView.error("Failed to load reaction picker: \(error)")
      }
    case .copyMessageLink:
      guard case .eventId(let eventId) = event.eventOrTransactionId else { return }
      let room = timeline.room.room
      startActionTask {
        do {
          let permalink = try await room.matrixToEventPermalink(eventId: eventId)
          guard !Task.isCancelled else { return }
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(permalink, forType: .string)
        } catch {
          guard !Task.isCancelled else { return }
          Logger.timelineTableView.error("Failed to copy message link: \(error)")
        }
      }
    case .retrySend:
      guard case .sendingFailed = event.localSendState,
        let sendHandle = event.lazyProvider.getSendHandle()
      else { return }
      let room = timeline.room.room
      startActionTask {
        // A network failure turned the room's send queue off; an unrecoverable one parked the
        // message. Undo both, so the message goes out whichever it was.
        room.enableSendQueue(enable: true)
        do {
          try await sendHandle.tryResend()
        } catch {
          guard !Task.isCancelled else { return }
          Logger.timelineTableView.error("Failed to retry sending message: \(error)")
        }
      }
    case .showSource:
      MessageSourceWindowController.show(source: event.lazyProvider.latestJson())
    case .downloadToFile(let index):
      let attachments = MessageDownloadAttachment.attachments(for: event)
      guard attachments.indices.contains(index) else { return }
      startActionTask { [weak self] in
        guard let self = self, let matrixClient = windowState.matrixClient else { return }
        await MessageDownloadAttachment.downloadToFile(
          view: view, matrixClient: matrixClient, attachment: attachments[index])
      }
    case .delete:
      guard canDeleteMessage(event), let window = view.window else { return }
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = String(localized: "Delete message?")
      alert.informativeText =
        String(
          localized:
            "This will remove the message for everyone in the room. This action cannot be undone.")
      let deleteButton = alert.addButton(withTitle: String(localized: "Delete"))
      deleteButton.hasDestructiveAction = true
      alert.addButton(withTitle: String(localized: "Cancel"))
      startActionTask { [weak self] in
        let response = await alert.beginSheetModal(for: window)
        guard response == .alertFirstButtonReturn, !Task.isCancelled,
          let self, self.canDeleteMessage(event)
        else { return }
        do {
          try await self.timeline.timeline?.redactEvent(
            eventOrTransactionId: event.eventOrTransactionId, reason: nil)
        } catch {
          guard !Task.isCancelled else { return }
          Logger.timelineTableView.error("Failed to delete message: \(error)")
        }
      }
    case .edit:
      beginEditing(event: event)
    case .reply:
      composer.beginReply(to: event)
    case .replyInThread:
      windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
    case .pin:
      guard case .eventId(eventId: let eventId) = event.eventOrTransactionId else { return }
      startActionTask { [weak self] in
        guard let self, let sdkTimeline = self.timeline.timeline else { return }
        let isPinned = self.isMessagePinned(event)
        do {
          if isPinned {
            _ = try await sdkTimeline.unpinEvent(eventId: eventId)
          } else {
            _ = try await sdkTimeline.pinEvent(eventId: eventId)
          }
        } catch {
          guard !Task.isCancelled else { return }
          Logger.timelineTableView.error(
            "Failed to \(isPinned ? "unpin" : "pin") message: \(error)")
        }
      }
    }
  }

  private var typingNames: [String] {
    let members = timeline.room.members
    return timeline.room.typingUserIds.map { userId in
      ContactDirectory.shared.resolvedName(
        userID: userId, matrixName: members.first(where: { $0.userId == userId })?.displayName)
    }
  }

  /// Redraws visible rows when linked contacts or contact settings change.
  private func listenForContactChanges() {
    withObservationTracking {
      _ = ContactDirectory.shared.revision
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.listenForContactChanges()
        let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
        guard visibleRows.length > 0 else { return }
        self.tableView.reloadData(
          forRowIndexes: IndexSet(integersIn: visibleRows.location..<NSMaxRange(visibleRows)),
          columnIndexes: IndexSet(integer: 0))
      }
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

  private func listenForTimelinePagination() {
    guard !tornDown else { return }
    let state = withObservationTracking {
      (
        fetchingOlder: timeline.fetchingOlderMessages,
        fetchingNewer: timeline.fetchingNewerMessages,
        isConfigured: timeline.isConfigured
      )
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.listenForTimelinePagination()
      }
    }
    updatePaginationSpinners(showTop: state.fetchingOlder, showBottom: state.fetchingNewer)
    if !state.fetchingNewer {
      returnToLiveIfNeeded()
    }
    if state.isConfigured {
      positionInitiallyIfNeeded()
      paginateIfNeeded(onlyIfUnderfilled: true)
    }
  }

  private func updatePaginationSpinners(showTop: Bool, showBottom: Bool) {
    guard showTop != showTopPaginationSpinner || showBottom != showBottomPaginationSpinner
    else { return }

    updateTimelineRows(revealingTopSpinner: showTop && !showTopPaginationSpinner) {
      showTopPaginationSpinner = showTop
      showBottomPaginationSpinner = showBottom
      return []
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

  private var timelineFetchTask: Task<Void, Never>?
  private var timelineForwardFetchTask: Task<Void, Never>?
  private var lastAutoFillItemCount: Int?
  private var didScrolToBottom = false

  @objc private func userDidScroll(_ notification: Notification) {
    guard positionedInitially, !updatingTimelineItems, !tornDown,
      timeline.focusedEventId != nil
    else { return }
    didScrolToBottom = documentView.isAtBottom
    returnToLiveIfNeeded()
  }

  private func returnToLiveIfNeeded() {
    guard timeline.focusedEventId != nil, timeline.hitTimelineEnd, didScrolToBottom, !tornDown,
      !showBottomPaginationSpinner, documentView.isAtBottom
    else { return }
    windowState.returnToLive(from: timeline)
  }

  @objc func viewDidScroll(_ notification: Notification) {
    guard positionedInitially, !updatingTimelineItems, !tornDown else { return }
    closeReactionPicker()
    paginateIfNeeded()
  }

  private func paginateIfNeeded(onlyIfUnderfilled: Bool = false) {
    guard positionedInitially, !updatingTimelineItems, !tornDown, timeline.isConfigured else {
      return
    }
    let underfilled = tableView.bounds.height < scrollView.contentView.bounds.height
    if onlyIfUnderfilled {
      guard timeline.focusedEventId != nil, underfilled, timeline.paginationErrorMessage == nil,
        lastAutoFillItemCount != timeline.timelineItems.count
      else { return }
    }

    let threshold: CGFloat = 200
    let distanceFromTop = tableView.visibleRect.minY - tableView.bounds.minY
    let distanceFromBottom = documentView.bottomAlignedOriginY - scrollView.contentView.bounds.minY
    var requested = false

    // Fetch older messages
    if underfilled || distanceFromTop <= threshold, timelineFetchTask == nil,
      !timeline.fetchingOlderMessages, !timeline.hitTimelineStart
    {
      requested = true
      timelineFetchTask = Task { [weak self] in
        await self?.timeline.fetchOlderMessages()
        self?.timelineFetchTask = nil
        self?.paginateIfNeeded(onlyIfUnderfilled: true)
      }
    }

    // Fetch newer messages
    if underfilled || distanceFromBottom <= threshold, timelineForwardFetchTask == nil,
      timeline.focusedEventId != nil, !timeline.fetchingNewerMessages, !timeline.hitTimelineEnd
    {
      requested = true
      timelineForwardFetchTask = Task { [weak self] in
        await self?.timeline.fetchNewerMessages()
        self?.timelineForwardFetchTask = nil
        self?.paginateIfNeeded(onlyIfUnderfilled: true)
      }
    }

    // An empty or fully filtered page must not cause an automatic request loop.
    if requested { lastAutoFillItemCount = timeline.timelineItems.count }
  }

  func rowForEventId(id eventId: MatrixRustSDK.EventOrTransactionId) -> Int? {
    timelineItems.firstIndex { item in
      switch item {
      case .message(item: _, let event, content: _):
        return event.eventOrTransactionId == eventId
      case .state(let entries):
        return entries.contains { $0.event.eventOrTransactionId == eventId }
      default:
        return false
      }
    }
  }

  func focusTimelineEvent(id eventId: MatrixRustSDK.EventOrTransactionId) {
    guard let rowIndex = rowForEventId(id: eventId) else { return }

    tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
    updateSelectedMessage(makeActive: true)
    tableView.animateRowToVisible(rowIndex)
  }

  func selectedMessageEvent(matching messageID: String) -> MatrixRustSDK.EventTimelineItem? {
    let row = tableView.selectedRow
    guard timelineItems.indices.contains(row), timelineItems[row].id == messageID,
      case .message(_, let event, _) = timelineItems[row]
    else { return nil }
    return event
  }

  private func updateConversationSelection(makeActive: Bool) {
    // Background updates to another timeline must not take over the scene's commands.
    guard makeActive || windowState.conversationSelection?.owner === self else { return }
    let row = tableView.selectedRow
    guard timelineItems.indices.contains(row), case .message = timelineItems[row] else {
      windowState.conversationSelection = nil
      return
    }
    windowState.conversationSelection = ConversationMessageSelection(
      owner: self, messageID: timelineItems[row].id)
  }

  private func updateSelectedMessage(makeActive: Bool = false) {
    updateConversationSelection(makeActive: makeActive)
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
    updateSelectedMessage(makeActive: true)
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
        updateSelectedMessage(makeActive: true)
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
    guard !documentView.shouldFollowBottom else { return [] }
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
      case .profile, .virtual, .typingIndicator, .paginationSpinner:
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
    updateTimelineRows {
      let change = projection.apply(diffs)
      assert(
        projection.sourceItems.map { $0.uniqueId().id }
          == timeline.timelineItems.map { $0.uniqueId().id }
      )
      return change.changedIDs
    }
    positionInitiallyIfNeeded()
    paginateIfNeeded(onlyIfUnderfilled: true)
  }

  private func updateTimelineRows(
    revealingTopSpinner: Bool = false, _ update: () -> Set<String>
  ) {
    let clipView = scrollView.contentView
    let followBottom = documentView.shouldFollowBottom
    let oldOrigin = clipView.bounds.origin
    // At the top edge, anchoring to the first message would hide the new spinner.
    let keepTopVisible =
      revealingTopSpinner && tableView.visibleRect.minY - tableView.bounds.minY <= 2
    let candidates = keepTopVisible ? [] : readingAnchorCandidates()

    // Layout and scroll restoration may send bounds notifications. Do not fetch
    // more history based on an intermediate viewport position.
    updatingTimelineItems = true
    defer {
      updatingTimelineItems = false
      positionHoverOverlay()
      updateReactionPickerAnchor()
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false

      applyProjectedRows(changedIDs: update())

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
  }

  private func applyProjectedRows(changedIDs: Set<String>) {
    let wasUpdating = updatingTimelineItems
    updatingTimelineItems = true
    defer { updatingTimelineItems = wasUpdating }

    let oldIDs = timelineItems.map(\.id)
    let selectedId =
      oldIDs.indices.contains(tableView.selectedRow) ? oldIDs[tableView.selectedRow] : nil
    var rows = projection.rows
    if showTopPaginationSpinner {
      rows.insert(.paginationSpinner(position: .top), at: 0)
    }
    if showBottomPaginationSpinner {
      // Keep the typing indicator last, where the typing listener expects it.
      let index = rows.last?.id == "typing-indicator" ? rows.count - 1 : rows.count
      rows.insert(.paginationSpinner(position: .bottom), at: index)
    }
    timelineItems = rows
    let newIDs = rows.map(\.id)
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

extension TimelineViewController: NSPopoverDelegate {
  private func showReactionPicker(
    for event: MatrixRustSDK.EventTimelineItem, source: ReactionPickerPresentationSource
  ) throws {
    guard view.window != nil, !hoverOverlay.isPresentingInteraction,
      let row = rowForEventId(id: event.eventOrTransactionId)
    else { return }
    let messageID = timelineItems[row].id
    if reactionPickerMessageID == messageID {
      closeReactionPicker(restoreFocus: true)
      return
    }
    closeReactionPicker()
    let usesHoverAnchor =
      source == .hoverButton && hoveredMessageId == messageID
      && hoverOverlay.reactionPickerAnchorView != nil
    if !usesHoverAnchor {
      hideHoverOverlay()
      // Reveal the row first so AppKit creates its real, laid-out content view.
      tableView.scrollRowToVisible(row)
    }
    scrollView.layoutSubtreeIfNeeded()
    guard
      let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
        as? MessageRowView
    else { return }
    if !usesHoverAnchor {
      let anchor = tableView.convert(rowView.reactionPickerAnchorRect, from: rowView)
      // A tall message may not fit in the viewport; reveal the anchor itself.
      tableView.scrollToVisible(anchor.insetBy(dx: -8, dy: -8))
      scrollView.layoutSubtreeIfNeeded()
    }
    let anchor = reactionPickerAnchor(for: rowView, messageID: messageID, source: source)

    let picker = ReactionPickerViewController(
      model: try ReactionPickerModel.loadBundled(),
      recentReactions: windowState.matrixClient?.recentReactions)
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = picker
    popover.contentSize = ReactionPickerViewController.contentSize
    popover.delegate = self
    picker.onDismiss = { [weak self, weak popover] in
      guard let self, let popover, self.reactionPickerPopover === popover else { return }
      self.closeReactionPicker(restoreFocus: true)
    }
    picker.onSelect = { [weak self, weak popover] key in
      guard let self, let popover, self.reactionPickerPopover === popover else { return }
      let currentEvent = self.reactionPickerEvent()
      self.closeReactionPicker(restoreFocus: true)
      if let currentEvent, self.canPerformMessageAction(.reaction(key), for: currentEvent) {
        self.toggleReaction(key, for: currentEvent)
      }
    }
    reactionPickerMessageID = messageID
    reactionPickerSource = source
    reactionPickerPopover = popover
    popover.show(relativeTo: anchor.rect, of: tableView, preferredEdge: anchor.edge)
  }

  private func reactionPickerAnchor(
    for rowView: MessageRowView, messageID: String?, source: ReactionPickerPresentationSource
  ) -> (rect: NSRect, edge: NSRectEdge) {
    if source == .hoverButton, hoveredMessageId == messageID,
      let button = hoverOverlay.reactionPickerAnchorView
    {
      return (tableView.convert(button.bounds, from: button), .maxY)
    }
    return (tableView.convert(rowView.reactionPickerAnchorRect, from: rowView), .maxX)
  }

  private func reactionPickerEvent() -> MatrixRustSDK.EventTimelineItem? {
    guard let messageID = reactionPickerMessageID,
      let item = timelineItems.first(where: { $0.id == messageID }),
      case .message(_, let event, _) = item
    else { return nil }
    return event
  }

  private func updateReactionPickerAnchor() {
    guard !updatingTimelineItems, !updatingReactionPickerAnchor,
      let popover = reactionPickerPopover
    else { return }
    updatingReactionPickerAnchor = true
    defer { updatingReactionPickerAnchor = false }
    guard let event = reactionPickerEvent(), canPerformMessageAction(.reactionPicker, for: event),
      let row = rowForEventId(id: event.eventOrTransactionId),
      let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
        as? MessageRowView
    else {
      closeReactionPicker()
      return
    }
    let anchor = reactionPickerAnchor(
      for: rowView, messageID: reactionPickerMessageID,
      source: reactionPickerSource ?? .selectedMessage)
    let visibleRect = tableView.convert(scrollView.contentView.bounds, from: scrollView.contentView)
    guard visibleRect.intersects(anchor.rect) else {
      closeReactionPicker()
      return
    }
    popover.positioningRect = anchor.rect
  }

  private func closeReactionPicker(restoreFocus: Bool = false) {
    guard let popover = reactionPickerPopover else { return }
    let shouldRestoreFocus =
      restoreFocus && reactionPickerSource == .selectedMessage
      && reactionPickerMessageID == windowState.conversationSelection?.messageID
      && windowState.conversationSelection?.owner === self
    let wasHoverPresentation = isHoverReactionPickerOpen
    reactionPickerPopover = nil
    reactionPickerMessageID = nil
    reactionPickerSource = nil
    (popover.contentViewController as? ReactionPickerViewController)?.stopLoadingRecents()
    popover.delegate = nil
    popover.close()
    if wasHoverPresentation { hideHoverOverlay() }
    if shouldRestoreFocus, let window = view.window, window.isKeyWindow {
      window.makeFirstResponder(tableView)
    }
  }

  func popoverDidClose(_ notification: Notification) {
    guard let popover = notification.object as? NSPopover, reactionPickerPopover === popover else {
      return
    }
    // Transient dismissal (outside clicks/window changes) must not reclaim focus.
    closeReactionPicker()
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
    updateSelectedMessage(makeActive: true)
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    let item = timelineItems[row]

    if case .profile = item {
      return MessageProfileRowView.rowHeight
    }

    if case .typingIndicator = item {
      return TypingIndicatorRowView.rowHeight
    }

    if case .paginationSpinner = item {
      return PaginationSpinnerRowView.rowHeight
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
    state.imageLoader = windowState.matrixClient
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
      (superview as? TimelineDocumentView)?.shouldFollowBottom ?? false
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
  private let allowsBottomFollowing: Bool
  private var updatingGeometry = false
  private var previousViewportHeight: CGFloat?
  private var previousBottomInset: CGFloat?

  override var isFlipped: Bool { true }

  init(tableView: TimelineTableView, allowsBottomFollowing: Bool) {
    self.tableView = tableView
    self.allowsBottomFollowing = allowsBottomFollowing
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

  var shouldFollowBottom: Bool { allowsBottomFollowing && isAtBottom }

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
      allowsBottomFollowing && (resized || bottomInsetChanged)
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

/// A message action waiting on a menu item, which can only hold an object.
private final class PendingMessageAction: NSObject {
  let action: MessageHoverOverlayView.Action
  let event: MatrixRustSDK.EventTimelineItem

  init(action: MessageHoverOverlayView.Action, event: MatrixRustSDK.EventTimelineItem) {
    self.action = action
    self.event = event
  }
}

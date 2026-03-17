import AppKit
import MatrixRustSDK
import OSLog
import SwiftUI
import UI

enum TimelineItemRowInfo {
    case message(event: EventTimelineItem, content: MsgLikeContent)
    case state(event: EventTimelineItem)
    case virtual(virtual: VirtualTimelineItem)

    var reuseIdentifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .message:
            return NSUserInterfaceItemIdentifier("message")
        case .state:
            return NSUserInterfaceItemIdentifier("state")
        case .virtual:
            return NSUserInterfaceItemIdentifier("virtual")
        }
    }
}

struct TimelineItemRowView: View {
    let rowInfo: TimelineItemRowInfo
    let timeline: LiveTimeline?
    let includeProfileHeader: Bool

    let appState: AppState
    let windowState: WindowState

    init(rowInfo: TimelineItemRowInfo, timeline: LiveTimeline?, includeProfileHeader: Bool = true, coordinator: TimelineViewRepresentable.Coordinator) {
        self.rowInfo = rowInfo
        self.timeline = timeline
        self.includeProfileHeader = includeProfileHeader
        self.appState = coordinator.appState
        self.windowState = coordinator.windowState
    }

    @ViewBuilder
    var contentView: some View {
        switch rowInfo {
        case .message(let event, let content):
            ChatMessageView(timeline: timeline, event: event, msg: content, includeProfileHeader: includeProfileHeader)
        case .state(let event):
            UI.GenericEventView(event: event, name: event.content.description)
        case .virtual(let virtual):
            UI.VirtualItemView(item: virtual.asModel)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                contentView
                    .environment(appState)
                    .environment(windowState)
            }
        }
    }
}

extension TimelineItem {
    var rowInfo: TimelineItemRowInfo {
        if let virtual = asVirtual() {
            return .virtual(virtual: virtual)
        }

        if let event = asEvent() {
            switch event.content {
            case .msgLike(content: let content):
                return .message(event: event, content: content)
            default:
                return .state(event: event)
            }
        }

        fatalError("unreachable state: item must be either virtual or event")
    }
}

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    let timeline: LiveTimeline
    var timelineItems: [TimelineItem]
    var rowHeights: [Int: CGFloat] = [:]
    private var pendingHeightUpdate = false

    private let hoverPanel = HoverActionsPanel()
    private var hideTimer: Timer?

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.timelineItems = timelineItems
        super.init(nibName: nil, bundle: nil)
    }

    /// Whether the message at `row` is the first in a consecutive group from the same sender.
    /// The table is reversed (bottom-sticky), so the visually previous item is at row + 1.
    func shouldIncludeProfileHeader(at row: Int) -> Bool {
        guard case .message(let event, _) = timelineItems[row].rowInfo else { return true }
        let previousRow = row + 1
        guard previousRow < timelineItems.count,
              case .message(let previousEvent, _) = timelineItems[previousRow].rowInfo,
              previousEvent.sender == event.sender else { return true }
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none

        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = 60

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self else { return NSView() }

            let item = timelineItems[row]
            let view = TimelineItemRowView(rowInfo: item.rowInfo, timeline: timeline, includeProfileHeader: shouldIncludeProfileHeader(at: row), coordinator: coordinator)

            let hostView: SelfSizingHostingView<TimelineItemRowView>
            if let recycledView = tableView.makeView(withIdentifier: item.rowInfo.reuseIdentifier, owner: self)
                as? SelfSizingHostingView<TimelineItemRowView>
            {
                recycledView.rootView = view
                hostView = recycledView
            } else {
                hostView = SelfSizingHostingView<TimelineItemRowView>(rootView: view)
                hostView.identifier = item.rowInfo.reuseIdentifier
                hostView.sizingOptions = []
                hostView.autoresizingMask = [.width, .height]
            }
            hostView.row = row
            hostView.controller = self

            return hostView
        }

        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        view = scrollView

        // Hover actions panel
        tableView.onHoveredRowChanged = { [weak self] row in
            self?.handleHoveredRowChanged(row)
        }

        // Subscribe to view resize notifications
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissHoverPanelNotification),
            name: NSWindow.didMoveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissHoverPanelNotification),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissHoverPanelNotification),
            name: NSWindow.willEnterFullScreenNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismissHoverPanelNotification),
            name: NSWindow.willExitFullScreenNotification,
            object: nil
        )

        tableView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableDidResize),
            name: NSView.frameDidChangeNotification,
            object: tableView
        )

        listenForFocusTimelineItem()
    }

    @objc func windowDidResignKey(_ notification: Notification) {
        dismissHoverPanel()
    }

    @objc func dismissHoverPanelNotification(_ notification: Notification) {
        dismissHoverPanel()
    }

    @objc func tableDidResize(_ notification: Notification) {
        dismissHoverPanel()
    }

    func dismissHoverPanel() {
        hoverPanel.orderOut(nil)
        timeline.hoveredEventId = nil
    }

    private func repositionHoverPanel() {
        if let hoveredRow = tableView.hoveredRow {
            handleHoveredRowChanged(hoveredRow)
        } else {
            dismissHoverPanel()
        }
    }

    var timelineFetchTask: Task<Void, Never>?

    @objc func viewDidScroll(_ notification: Notification) {
        dismissHoverPanel()

        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

        let distanceFromTop = timelineHeight - viewHeight - currentOffset
        let threshold: CGFloat = 200.0 // Pixels from the top to trigger load

        if distanceFromTop <= threshold, timelineFetchTask == nil {
            Logger.timelineTableView.info("Fetching older messages (scroll near top)")
            timelineFetchTask = Task {
                do {
                    try await timeline.fetchOlderMessages()
                } catch {
                    Logger.timelineTableView.error("Failed to fetch older messages: \(error)")
                }

                timelineFetchTask = nil
            }
        }
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: {
            Task { @MainActor in self.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId,
              let rowIndex = timelineItems.firstIndex(where: {
                  $0.asEvent()?.eventOrTransactionId == focusedTimelineEventId
              }) else { return }

        tableView.animateRowToVisible(rowIndex)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    // MARK: - Hover actions panel

    private func handleHoveredRowChanged(_ row: Int?) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard let row,
              case .message(let event, _) = timelineItems[row].rowInfo else {
            // Delay hiding so mouse can move from row to panel
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self else { return }
                if !self.hoverPanel.isMouseInside {
                    self.dismissHoverPanel()
                }
            }
            return
        }

        let timeline = self.timeline
        let windowState = self.coordinator.windowState

        timeline.hoveredEventId = event.eventOrTransactionId
        hoverPanel.update(
            eventId: event.eventOrTransactionId.id,
            onReaction: { key in
                Task {
                    guard let inner = timeline.timeline else { return }
                    do {
                        let _ = try await inner.toggleReaction(itemId: event.eventOrTransactionId, key: key)
                    } catch {
                        Logger.timelineTableView.error("Failed to toggle reaction: \(error)")
                    }
                }
            },
            onReply: {
                timeline.sendReplyTo = event
            },
            onReplyInThread: { windowState.focusThread(rootEventId: event.eventOrTransactionId.id) },
            onPin: {
                guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
                Task {
                    do {
                        let _ = try await timeline.timeline?.pinEvent(eventId: eventId)
                    } catch {
                        Logger.timelineTableView.error("Failed to pin message: \(error)")
                    }
                }
            }
        )

        // Position relative to the row, offset past profile header if present
        let rowRect = tableView.rect(ofRow: row)
        guard tableView.visibleRect.contains(CGPoint(x: rowRect.midX, y: rowRect.maxY)) else {
            return dismissHoverPanel()
        }
        let rowRectInWindow = tableView.convert(rowRect, to: nil)
        let profileHeaderOffset: CGFloat = shouldIncludeProfileHeader(at: row) ? 32 : 0
        if let window = tableView.window {
            hoverPanel.position(relativeTo: rowRectInWindow, in: window, topOffset: profileHeaderOffset)
            if hoverPanel.parent != window {
                window.addChildWindow(hoverPanel, ordered: .above)
            }
            hoverPanel.orderFront(nil)
        }
    }

    enum TimelineSection {
        case main
        case typingIndicator
    }

    func updateTimelineItems(_ timelineItems: [TimelineItem]) {
        Logger.timelineTableView.info("update timeline items")
        dismissHoverPanel()

        let oldIds = self.timelineItems.map { $0.uniqueId().id }
        self.timelineItems = timelineItems.reversed()
        let newIds = self.timelineItems.map { $0.uniqueId().id }

        // If the IDs haven't changed, reload all rows in place (content-only update: reactions, read receipts, etc.)
        // Reloads all rows rather than just visible ones to avoid stale content in NSTableView's prepared/cached views.
        if oldIds == newIds {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<self.timelineItems.count),
                                 columnIndexes: IndexSet(integer: 0))
            repositionHoverPanel()
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in self.timelineItems {
            snapshot.appendItems([.init(id: item.uniqueId().id)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        repositionHoverPanel()

        // Re-measure visible rows after hosting views settle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rowHeights.removeAll()
            self.scheduleHeightUpdate()
        }
    }
}

extension TimelineViewController: NSTableViewDelegate {
    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return rowHeights[row] ?? 60
    }

    func scheduleHeightUpdate() {
        guard !pendingHeightUpdate else { return }
        pendingHeightUpdate = true
        DispatchQueue.main.async { [weak self] in
            self?.pendingHeightUpdate = false
            self?.updateVisibleRowHeights()
        }
    }

    private func updateVisibleRowHeights() {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        var changed = IndexSet()
        for row in visibleRows.lowerBound..<visibleRows.upperBound {
            guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? SelfSizingHostingView<TimelineItemRowView> else { continue }
            let h = cellView.measureHeight()
            if h > 0, abs(h - (rowHeights[row] ?? 60)) > 1 {
                rowHeights[row] = h
                changed.insert(row)
            }
        }
        if !changed.isEmpty {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            tableView.noteHeightOfRows(withIndexesChanged: changed)
            NSAnimationContext.endGrouping()
        }
    }
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }

    var onHoveredRowChanged: ((Int?) -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var hoveredRow: Int? = nil

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let newRow = row >= 0 ? row : nil
        if newRow != hoveredRow {
            hoveredRow = newRow
            onHoveredRowChanged?(newRow)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRow = nil
        onHoveredRowChanged?(nil)
    }
}

class SelfSizingHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: TimelineViewController?
    var row: Int = 0

    override func layout() {
        super.layout()
        controller?.scheduleHeightUpdate()
    }

    override func invalidateIntrinsicContentSize() {
        // Don't call super — prevents constraint loop
        // Instead schedule a deferred height update
        controller?.scheduleHeightUpdate()
    }

    func measureHeight() -> CGFloat {
        let width = frame.width
        guard width > 0 else { return 0 }
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.preferredContentSize]
        let size = controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return max(size.height, 1)
    }
}

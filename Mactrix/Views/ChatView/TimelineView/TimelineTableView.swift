import AppKit
import MatrixRustSDK
import OSLog
import SwiftUI
import UI

enum TimelineItemRowInfo {
    case profile(item: TimelineItem, event: EventTimelineItem)
    case message(item: TimelineItem, event: EventTimelineItem, content: MsgLikeContent)
    case state(item: TimelineItem, event: EventTimelineItem)
    case virtual(item: TimelineItem, virtual: VirtualTimelineItem)

    var reuseIdentifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .profile(profile: _):
            return NSUserInterfaceItemIdentifier("profile")
        case .message:
            return NSUserInterfaceItemIdentifier("message")
        case .state:
            return NSUserInterfaceItemIdentifier("state")
        case .virtual:
            return NSUserInterfaceItemIdentifier("virtual")
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
        }
    }
}

struct TimelineItemRowView: View {
    let rowInfo: TimelineItemRowInfo
    let timeline: LiveTimeline?

    let appState: AppState
    let windowState: WindowState

    init(rowInfo: TimelineItemRowInfo, timeline: LiveTimeline?, coordinator: TimelineViewRepresentable.Coordinator) {
        self.rowInfo = rowInfo
        self.timeline = timeline
        self.appState = coordinator.appState
        self.windowState = coordinator.windowState
    }

    @ViewBuilder
    var contentView: some View {
        switch rowInfo {
        case .profile(_, let event):
            UI.MessageEventProfileView(event: event, focusUserAction: { windowState.focusUser(userId: event.sender) }, imageLoader: appState.matrixClient)
        case .message(_, let event, let content):
            ChatMessageView(timeline: timeline, event: event, msg: content, includeProfileHeader: false)
        case .state(_, let event):
            UI.GenericEventView(event: event, name: event.content.description)
        case .virtual(_, let virtual):
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

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    let timeline: LiveTimeline
    var timelineItems: [TimelineItemRowInfo] = []

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        super.init(nibName: nil, bundle: nil)
        self.timelineItems = mapTimelineItems(items: timelineItems)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none

        tableView.rowHeight = -1
        tableView.usesAutomaticRowHeights = true

        oldWidth = tableView.frame.width

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self else { return NSView() }

            let item = timelineItems[row]

            if case .profile(item: _, event: let event) = item {
                if let recycledView = tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
                    as? MessageProfileRowView
                {
                    recycledView.configure(event: event)
                    return recycledView
                } else {
                    let view = MessageProfileRowView()
                    view.initialize(imageLoader: coordinator.appState.matrixClient, focusUser: { [weak self] in
                        self?.coordinator.windowState.focusUser(userId: $0)
                    })
                    view.configure(event: event)
                    view.identifier = item.reuseIdentifier
                    return view
                }
            }

            let view = TimelineItemRowView(rowInfo: item, timeline: timeline, coordinator: coordinator)
            let hostView: NSHostingView<TimelineItemRowView>
            if let recycledView = tableView.makeView(withIdentifier: item.reuseIdentifier, owner: self)
                as? NSHostingView<TimelineItemRowView>
            {
                recycledView.rootView = view
                hostView = recycledView
            } else {
                hostView = NSHostingView<TimelineItemRowView>(rootView: view)
                hostView.identifier = item.reuseIdentifier
                hostView.autoresizingMask = [.width, .height]
                hostView.sizingOptions = [.preferredContentSize]
                hostView.setContentHuggingPriority(.required, for: .vertical)
            }

            return hostView
        }

        tableView.delegate = self

        scrollView.documentView = tableView
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

        listenForFocusTimelineItem()
    }

    @objc func handleTableResize(_ notification: Notification) {
        if oldWidth != tableView.frame.width {
            oldWidth = tableView.frame.width

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                let visibleRect = tableView.visibleRect
                let visibleRows = tableView.rows(in: visibleRect)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
            }
        }
    }

    var timelineFetchTask: Task<Void, Never>?

    @objc func viewDidScroll(_ notification: Notification) {
        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

        let distanceFromTop = timelineHeight - viewHeight - currentOffset
        let threshold: CGFloat = 200.0 // Pixels from the top to trigger load

        if distanceFromTop <= threshold, timelineFetchTask == nil {
            Logger.timelineTableView.info("Fetching older messages (scroll near top)")
            timelineFetchTask = Task {
                await timeline.fetchOlderMessages()
                timelineFetchTask = nil
            }
        }
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: { [weak self] in
            Task { @MainActor in self?.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId,
              let rowIndex = timelineItems.firstIndex(where: { item in
                  switch item {
                  case .message(item: _, event: let event, content: _):
                      return event.eventOrTransactionId == focusedTimelineEventId
                  default:
                      return false
                  }
              }) else { return }

        tableView.animateRowToVisible(rowIndex)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    enum TimelineSection {
        case main
        case typingIndicator
    }

    func updateTimelineItems(_ timelineItems: [TimelineItem]) {
        Logger.timelineTableView.info("update timeline items")

        let oldIds = self.timelineItems.map { $0.id }
        self.timelineItems = mapTimelineItems(items: timelineItems)
        let newIds = self.timelineItems.map { $0.id }

        // If the IDs haven't changed, reload all rows in place (content-only update: reactions, read receipts, etc.)
        // Reloads all rows rather than just visible ones to avoid stale content in NSTableView's prepared/cached views.
        if oldIds == newIds {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0 ..< self.timelineItems.count),
                                 columnIndexes: IndexSet(integer: 0))
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in self.timelineItems {
            snapshot.appendItems([.init(id: item.id)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        // Re-measure visible rows after hosting views settle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
        }
    }

    private func mapTimelineItems(items: [TimelineItem]) -> [TimelineItemRowInfo] {
        var result = [TimelineItemRowInfo]()

        var currentSender: String? = nil
        for item in items {
            if let event = item.asEvent() {
                switch event.content {
                case .msgLike(content: let content):
                    if event.sender != currentSender {
                        currentSender = event.sender
                        result.append(.profile(item: item, event: event))
                    }
                    result.append(.message(item: item, event: event, content: content))
                default:
                    currentSender = nil
                    result.append(.state(item: item, event: event))
                }
            }

            if let virtual = item.asVirtual() {
                currentSender = nil
                result.append(.virtual(item: item, virtual: virtual))
            }
        }

        result.reverse()

        return result
    }

    // values used to track width changes
    var oldWidth: CGFloat?
    let measurementHostingView = {
        let hostView = NSHostingController(rootView: AnyView(EmptyView()))
        hostView.sizingOptions = [.preferredContentSize]
        return hostView
    }()
}

extension TimelineViewController: NSTableViewDelegate {
    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let item = timelineItems[row]

        if case .profile = item {
            return MessageProfileRowView.ROW_HEIGHT
        }

        measurementHostingView.rootView = AnyView(TimelineItemRowView(rowInfo: item, timeline: timeline, coordinator: coordinator))

        let targetWidth = tableView.tableColumns[0].width
        let proposedSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)

        let size = measurementHostingView.sizeThatFits(in: proposedSize)
        // Avoid undefined-height rows which can cause NSTableView layout issues
        return max(size.height, 1)
    }
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }
}

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
    let appState: AppState
    let windowState: WindowState

    init(rowInfo: TimelineItemRowInfo, coordinator: TimelineViewRepresentable.Coordinator) {
        self.rowInfo = rowInfo
        self.appState = coordinator.appState
        self.windowState = coordinator.windowState
    }

    @ViewBuilder
    var contentView: some View {
        switch rowInfo {
        case .message(let event, let content):
            ChatMessageView(timeline: nil, event: event, msg: content, includeProfileHeader: true)
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

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.timelineItems = timelineItems
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false

        tableView.rowHeight = -1
        tableView.usesAutomaticRowHeights = true

        oldWidth = tableView.frame.width

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self else { return NSView() }

            let item = timelineItems[row]
            let view = TimelineItemRowView(rowInfo: item.rowInfo, coordinator: coordinator)

            let hostView: NSHostingView<TimelineItemRowView>
            if let recycledView = tableView.makeView(withIdentifier: item.rowInfo.reuseIdentifier, owner: self)
                as? NSHostingView<TimelineItemRowView>
            {
                Logger.timelineTableView.debug("reusing message view")
                recycledView.rootView = view
                hostView = recycledView
            } else {
                hostView = NSHostingView<TimelineItemRowView>(rootView: view)
                hostView.identifier = item.rowInfo.reuseIdentifier
                hostView.autoresizingMask = [.width, .height]
                hostView.sizingOptions = [.preferredContentSize]
                hostView.setContentHuggingPriority(.required, for: .vertical)
            }

            return hostView
        }

        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView

        // 1. Tell the clip view to post notifications when its bounds change (resize)
        scrollView.contentView.postsBoundsChangedNotifications = true

        // 2. Observe that notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc func handleTableResize(_ notification: Notification) {
        if oldWidth != tableView.frame.width {
            oldWidth = tableView.frame.width

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                // Update only the height of visible rows
                let visibleRect = tableView.visibleRect
                let visibleRows = tableView.rows(in: visibleRect)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
            }
        }
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
        self.timelineItems = timelineItems.reversed()

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in self.timelineItems {
            snapshot.appendItems([.init(id: item.uniqueId().id)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    // values used to calculate height of a row
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

        measurementHostingView.rootView = AnyView(TimelineItemRowView(rowInfo: item.rowInfo, coordinator: coordinator))

        let targetWidth = tableView.tableColumns[0].width
        let proposedSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)

        let size = measurementHostingView.sizeThatFits(in: proposedSize)
        Logger.timelineTableView.debug("Size of row \(row): \(size.height)")

        return size.height
    }
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }
}

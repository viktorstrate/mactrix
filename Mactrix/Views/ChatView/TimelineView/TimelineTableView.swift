import AppKit
import MatrixRustSDK
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

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, identifier in
            guard let self else { return NSView() }

            let hostView = tableView.makeView(withIdentifier: TimelineItemCell.reuseIdentifier, owner: self)
            print("Data source called \(row) \(identifier) \(hostView == nil ? "fresh" : "reuse")")

            let item = timelineItems[row]

            switch item.rowInfo {
            case .message(event: let event, content: let content):
                let view = ChatMessageView(timeline: nil, event: event, msg: content, includeProfileHeader: true)

                if let hostView = hostView as? NSHostingView<ChatMessageView> {
                    print("reusing message view")
                    hostView.rootView = view
                    return hostView
                } else {
                    let newHostView = NSHostingView<ChatMessageView>(rootView: view)
                    newHostView.identifier = TimelineItemCell.reuseIdentifier
                    return newHostView
                }
            case .state(event: let event):
                let view = UI.GenericEventView(event: event, name: event.content.description)

                if let hostView = hostView as? NSHostingView<UI.GenericEventView<EventTimelineItem>> {
                    print("reusing state view")
                    hostView.rootView = view
                    return hostView
                } else {
                    let newHostView = NSHostingView<UI.GenericEventView<EventTimelineItem>>(rootView: view)
                    newHostView.identifier = TimelineItemCell.reuseIdentifier
                    return newHostView
                }
            case .virtual(virtual: let virtual):
                let view = UI.VirtualItemView(item: virtual.asModel)

                if let hostView = hostView as? NSHostingView<UI.VirtualItemView> {
                    print("reusing virtual view")
                    hostView.rootView = view
                    return hostView
                } else {
                    let newHostView = NSHostingView<UI.VirtualItemView>(rootView: view)
                    newHostView.identifier = TimelineItemCell.reuseIdentifier
                    return newHostView
                }
            }
        }
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView
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
        print("update timeline items")
        self.timelineItems = timelineItems

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in timelineItems {
            snapshot.appendItems([.init(id: item.uniqueId().id)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)
    }
}

extension TimelineViewController: NSTableViewDelegate {
    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
}

class TimelineItemCell: NSTableCellView {
    static var reuseIdentifier: NSUserInterfaceItemIdentifier = .init("TimelineItemCell")
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }
}

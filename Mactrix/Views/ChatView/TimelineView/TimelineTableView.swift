import AppKit
import MatrixRustSDK
import SwiftUI
import UI

struct TimelineItemView: View {
    let item: TimelineItem

    var body: some View {
        if let virtual = item.asVirtual() {
            UI.VirtualItemView(item: virtual.asModel)
        } else if let event = item.asEvent() {
            if case let .msgLike(content: content) = event.content {
                ChatMessageView(timeline: nil, event: event, msg: content, includeProfileHeader: true)
            } else {
                Text("Not msg like")
            }
        } else {
            Text("Invalid timeline item")
        }
    }
}

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    var timelineItems: [TimelineItem]

    init(coordinator: TimelineViewRepresentable.Coordinator, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
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

        dataSource = .init(tableView: tableView) { [weak self] tableView, tableColumn, row, identifier in
            _ = tableView
            _ = tableColumn
            _ = row
            _ = identifier

            guard let self else { return NSView() }

            let hostView = tableView.makeView(withIdentifier: TimelineItemCell.reuseIdentifier, owner: self)
            print("Data source called \(row) \(identifier) \(hostView == nil ? "fresh" : "reuse")")

            // let view = Text("SwiftUI Text \(row)")

            let view = TimelineItemView(item: timelineItems[row])

            if let hostView = hostView as? NSHostingView<TimelineItemView> {
                print("reusing swift ui view")
                hostView.rootView = view
                return hostView
            }

            let newHostView = NSHostingView<TimelineItemView>(rootView: view)
            newHostView.identifier = TimelineItemCell.reuseIdentifier
            return newHostView
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

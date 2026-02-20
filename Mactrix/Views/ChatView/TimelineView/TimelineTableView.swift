import AppKit
import MatrixRustSDK
import SwiftUI

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = NSTableView()

    init(coordinator: TimelineViewRepresentable.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())

        dataSource = .init(tableView: tableView) { [weak self] tableView, tableColumn, row, identifier in
            _ = tableView
            _ = tableColumn
            _ = row
            _ = identifier

            let hostView = tableView.makeView(withIdentifier: TimelineItemCell.reuseIdentifier, owner: self)
            print("Data source called \(row) \(identifier) \(hostView == nil ? "fresh" : "reuse")")

            let view = Text("SwiftUI Text \(row)")

            if let hostView = hostView as? NSHostingView<Text> {
                print("reusing swift ui view")
                hostView.rootView = view
                return hostView
            }

            let newHostView = NSHostingView<Text>(rootView: view)
            newHostView.identifier = TimelineItemCell.reuseIdentifier
            return newHostView
        }
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView

        applySnapshot()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    enum TimelineSection {
        case main
        case typingIndicator
    }

    func applySnapshot() {
        guard let dataSource else { return }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()

        snapshot.appendSections([.main])
        for i in 0 ..< 10000 {
            snapshot.appendItems([.init(id: "item \(i)")], toSection: .main)
        }

        dataSource.apply(snapshot, animatingDifferences: false)
        print("Applied snapshot")
    }
}

extension TimelineViewController: NSTableViewDelegate {}

class TimelineItemCell: NSTableCellView {
    static var reuseIdentifier: NSUserInterfaceItemIdentifier = .init("TimelineItemCell")
}

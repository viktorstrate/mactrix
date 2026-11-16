import AppKit

final class ReactionPickerViewController: NSViewController {
  static let contentSize = NSSize(width: 320, height: 420)
  static let columnCount = 7
  static let recentItemLimit = columnCount * 3

  var onSelect: ((String) -> Void)?

  private let sections: [ReactionPickerModel.Section]
  private let collectionView = NSCollectionView()
  private let scrollView = NSScrollView()
  private let searchField = NSSearchField()
  private let categoryControl = NSSegmentedControl()
  private static let itemIdentifier = NSUserInterfaceItemIdentifier("reaction-emoji")
  private static let headerIdentifier = NSUserInterfaceItemIdentifier("reaction-category")

  init(model: ReactionPickerModel) {
    sections = model.sections(recentKeys: [], recentLimit: Self.recentItemLimit)
    super.init(nibName: nil, bundle: nil)
    preferredContentSize = Self.contentSize
  }

  override func loadView() {
    view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))

    searchField.placeholderString = String(localized: "Search")
    searchField.setAccessibilityLabel(String(localized: "Search emoji"))
    // Search and section navigation are connected in the next milestone.
    searchField.isEnabled = false
    searchField.toolTip = String(localized: "Emoji search is not available yet")

    categoryControl.segmentCount = sections.count
    categoryControl.segmentStyle = .smallSquare
    categoryControl.trackingMode = .selectOne
    categoryControl.controlSize = .small
    categoryControl.isEnabled = false
    categoryControl.setAccessibilityLabel(String(localized: "Emoji categories"))
    for (index, section) in sections.enumerated() {
      if let symbol = section.systemSymbolName {
        categoryControl.setImage(
          NSImage(systemSymbolName: symbol, accessibilityDescription: section.title),
          forSegment: index)
      }
      categoryControl.setToolTip(section.title, forSegment: index)
      categoryControl.setWidth(30, forSegment: index)
    }
    if !sections.isEmpty { categoryControl.selectedSegment = 0 }

    let layout = NSCollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    layout.itemSize = NSSize(width: 38, height: 38)
    layout.minimumInteritemSpacing = 4
    layout.minimumLineSpacing = 4
    layout.sectionInset = NSEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
    layout.headerReferenceSize = NSSize(width: Self.contentSize.width, height: 28)
    layout.sectionHeadersPinToVisibleBounds = false
    collectionView.collectionViewLayout = layout
    collectionView.backgroundColors = [.clear]
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = false
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.setAccessibilityLabel(String(localized: "Emoji"))
    collectionView.register(ReactionEmojiItem.self, forItemWithIdentifier: Self.itemIdentifier)
    collectionView.register(
      ReactionCategoryHeader.self,
      forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
      withIdentifier: Self.headerIdentifier)
    collectionView.frame = NSRect(x: 0, y: 0, width: Self.contentSize.width, height: 0)
    collectionView.autoresizingMask = [.width]

    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.scrollerStyle = .overlay
    scrollView.horizontalScrollElasticity = .none
    scrollView.documentView = collectionView

    let topSeparator = separator()
    let bottomSeparator = separator()
    for subview in [searchField, topSeparator, scrollView, bottomSeparator, categoryControl] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(subview)
    }
    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
      searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
      searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
      searchField.heightAnchor.constraint(equalToConstant: 24),
      topSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
      topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),
      bottomSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      categoryControl.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 6),
      categoryControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      categoryControl.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
      categoryControl.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    collectionView.reloadData()
  }

  private func separator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    return separator
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

extension ReactionPickerViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
  func numberOfSections(in collectionView: NSCollectionView) -> Int {
    sections.count
  }

  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int
  {
    sections[section].items.count
  }

  func collectionView(
    _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath)
    if let item = item as? ReactionEmojiItem {
      item.configure(sections[indexPath.section].items[indexPath.item])
    }
    return item
  }

  func collectionView(
    _ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String,
    at indexPath: IndexPath
  ) -> NSView {
    let header = collectionView.makeSupplementaryView(
      ofKind: kind, withIdentifier: Self.headerIdentifier, for: indexPath)
    (header as? ReactionCategoryHeader)?.configure(title: sections[indexPath.section].title)
    return header
  }

  func collectionView(
    _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    guard let indexPath = indexPaths.first else { return }
    onSelect?(sections[indexPath.section].items[indexPath.item].key)
  }
}

private final class ReactionEmojiItem: NSCollectionViewItem {
  override func loadView() {
    view = ReactionEmojiView()
  }

  func configure(_ item: ReactionPickerModel.Item) {
    (view as? ReactionEmojiView)?.configure(item)
    (view as? ReactionEmojiView)?.isSelected = isSelected
  }

  override var isSelected: Bool {
    didSet { (view as? ReactionEmojiView)?.isSelected = isSelected }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    (view as? ReactionEmojiView)?.resetHighlight()
  }
}

private final class ReactionEmojiView: NSView {
  private let label = NSTextField(labelWithString: "")
  private var isHovered = false
  var isSelected = false {
    didSet { updateAppearance() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
    label.font = .systemFont(ofSize: 27)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self, userInfo: nil))
  }

  func configure(_ item: ReactionPickerModel.Item) {
    label.stringValue = item.key
    toolTip = item.name
    setAccessibilityLabel(item.name)
  }

  func resetHighlight() {
    isHovered = false
    isSelected = false
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateAppearance()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateAppearance()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func updateAppearance() {
    layer?.backgroundColor =
      isSelected
      ? NSColor.selectedContentBackgroundColor.cgColor
      : isHovered ? NSColor.quaternaryLabelColor.cgColor : nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class ReactionCategoryHeader: NSView, NSCollectionViewElement {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func configure(title: String) {
    label.stringValue = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

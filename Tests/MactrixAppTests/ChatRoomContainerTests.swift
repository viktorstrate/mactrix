import AppKit
import MatrixRustSDK
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import MactrixApp

@MainActor
struct ChatRoomContainerTests {
  @Test(arguments: [false, true], [false, true])
  func explicitFramesFollowWideNarrowWideParent(hasReply: Bool, hasAttachments: Bool) {
    let room = makeRoom()
    room.composer.editor.string = String(repeating: "Wrapping editor text. ", count: 12)
    room.composer.setReply(details: hasReply ? longReply : nil)
    room.composer.setAttachments(hasAttachments ? (0..<8).map { _ in attachment() } : [])

    var heights: [CGFloat] = []
    for width: CGFloat in [800, 250, 800] {
      room.setFrameSize(NSSize(width: width, height: 2000))
      room.layoutSubtreeIfNeeded()
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)
      heights.append(room.composer.frame.height)
    }
    #expect(heights[1] > heights[0])
    #expect(heights[2] == heights[0])
    #expect(room.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    #expect(room.intrinsicContentSize.height == NSView.noIntrinsicMetric)
    for child in [room.timelineView, room.composer] {
      #expect(child.translatesAutoresizingMaskIntoConstraints)
      #expect(child.autoresizingMask.isEmpty)
    }
  }

  @Test func hostedRoomFitsAt250WithoutCustomMeasurement() {
    let room = makeRoom()
    room.composer.editor.string = String(repeating: "Wrapping editor text. ", count: 12)
    room.composer.setReply(details: longReply)
    room.composer.setAttachments((0..<8).map { _ in attachment() })
    let host = NSHostingView(
      rootView: RoomBridge(room: room).frame(minWidth: 250, minHeight: 200))

    var heights: [CGFloat] = []
    for width: CGFloat in [800, 250, 800, 250] {
      host.setFrameSize(NSSize(width: width, height: 2000))
      host.layoutSubtreeIfNeeded()
      room.layoutSubtreeIfNeeded()
      let rect = room.convert(room.bounds, to: host)
      #expect(abs(rect.minX) < 0.01)
      #expect(abs(rect.minY) < 0.01)
      #expect(abs(rect.width - width) < 0.01)
      #expect(abs(rect.height - host.bounds.height) < 0.01)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)
      heights.append(room.composer.frame.height)
    }
    #expect(heights[1] > heights[0])
    #expect(heights[2] == heights[0])
    #expect(heights[3] == heights[1])
  }

  @Test func contentInvalidationSchedulesParentLayoutAndReclaimsTimelineSpace() {
    let room = makeRoom()
    room.frame = NSRect(x: 0, y: 0, width: 250, height: 2000)
    room.layoutSubtreeIfNeeded()
    let emptyComposerFrame = room.composer.frame
    let emptyHeight = emptyComposerFrame.height
    let emptyTimelineHeight = room.timelineView.frame.height

    for _ in 0..<3 {
      // Match ChatInputViewController's text-change sizing path without a live room.
      room.composer.editor.string = String(repeating: "Wrapping text. ", count: 12)
      room.composer.invalidateSizing()
      #expect(room.needsLayout)
      #expect(room.composer.frame == emptyComposerFrame)
      room.layoutSubtreeIfNeeded()
      let textHeight = room.composer.frame.height
      #expect(textHeight > emptyHeight)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)

      room.composer.setReply(details: longReply)
      #expect(room.needsLayout)
      room.layoutSubtreeIfNeeded()
      let replyHeight = room.composer.frame.height
      #expect(replyHeight > textHeight)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)

      room.composer.setAttachments((0..<8).map { _ in attachment() })
      #expect(room.needsLayout)
      room.layoutSubtreeIfNeeded()
      let fullHeight = room.composer.frame.height
      #expect(fullHeight > replyHeight)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)

      room.composer.setReply(details: nil)
      #expect(room.needsLayout)
      room.layoutSubtreeIfNeeded()
      #expect(room.composer.frame.height < fullHeight)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)

      room.composer.setAttachments([])
      #expect(room.needsLayout)
      room.layoutSubtreeIfNeeded()
      #expect(room.composer.frame.height == textHeight)
      expectRoomGeometry(room)

      room.composer.editor.string = ""
      room.composer.invalidateSizing()
      #expect(room.needsLayout)
      room.layoutSubtreeIfNeeded()
      #expect(room.composer.frame.height == emptyHeight)
      #expect(room.timelineView.frame.height == emptyTimelineHeight)
      expectRoomGeometry(room)
      expectComposerContentFits(room.composer)
      #expect(!room.needsLayout)
    }
  }

  @Test func insufficientHeightClampsSiblingFramesWithoutNegativeTimelineHeight() {
    let room = makeRoom()
    room.composer.setReply(details: longReply)
    room.composer.setAttachments([attachment()])
    for height: CGFloat in [30, 0, 30] {
      room.setFrameSize(NSSize(width: 250, height: height))
      room.layoutSubtreeIfNeeded()
      expectRoomGeometry(room)
      #expect(room.timelineView.frame.height == 0)
    }
  }

  @Test func composerGrowAndShrinkFollowBottomOfRealTimeline() {
    let fixture = TimelineFixture(rowCount: 80)
    fixture.layout()
    fixture.table.scrollToBottom()
    let initialViewportHeight = fixture.scroll.contentView.bounds.height
    #expect(fixture.document.isAtBottom)

    for _ in 0..<3 {
      fixture.room.composer.setReply(details: .pending)
      fixture.room.composer.setAttachments([attachment()])
      #expect(fixture.room.needsLayout)
      fixture.layout()
      #expect(fixture.scroll.contentView.bounds.height < initialViewportHeight)
      #expect(fixture.document.isAtBottom)
      #expect(
        abs(fixture.scroll.contentView.bounds.minY - fixture.document.bottomAlignedOriginY) < 0.01)
      expectRoomGeometry(fixture.room)

      fixture.room.composer.setReply(details: nil)
      fixture.room.composer.setAttachments([])
      fixture.layout()
      #expect(abs(fixture.scroll.contentView.bounds.height - initialViewportHeight) < 0.01)
      #expect(fixture.document.isAtBottom)
      #expect(
        abs(fixture.scroll.contentView.bounds.minY - fixture.document.bottomAlignedOriginY) < 0.01)
      expectRoomGeometry(fixture.room)
    }
  }

  @Test func composerGrowAndShrinkPreserveOlderTimelinePosition() {
    let fixture = TimelineFixture(rowCount: 80)
    fixture.layout()
    let clip = fixture.scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: fixture.table.rect(ofRow: 10).minY + 7))
    fixture.scroll.reflectScrolledClipView(clip)
    let origin = clip.bounds.origin
    let visibleRow = fixture.table.row(at: fixture.table.convert(origin, from: fixture.document))
    #expect(visibleRow == 10)
    #expect(!fixture.document.isAtBottom)

    for _ in 0..<3 {
      for expanded in [true, false] {
        fixture.room.composer.setReply(details: expanded ? .pending : nil)
        fixture.room.composer.setAttachments(expanded ? [attachment()] : [])
        fixture.layout()
        #expect(abs(clip.bounds.minY - origin.y) < 0.01)
        #expect(
          fixture.table.row(at: fixture.table.convert(clip.bounds.origin, from: fixture.document))
            == visibleRow)
        #expect(!fixture.document.isAtBottom)
        expectRoomGeometry(fixture.room)
      }
    }
  }

  @Test func shortTimelineStaysBottomAlignedAsComposerChanges() {
    let fixture = TimelineFixture(rowCount: 2)
    fixture.layout()
    for _ in 0..<3 {
      for expanded in [true, false] {
        fixture.room.composer.setReply(details: expanded ? .pending : nil)
        fixture.room.composer.setAttachments(expanded ? [attachment()] : [])
        fixture.layout()
        let clip = fixture.scroll.contentView
        #expect(fixture.table.frame.height < clip.bounds.height)
        #expect(fixture.table.frame.minY > 0)
        #expect(abs(fixture.table.frame.maxY - fixture.document.bounds.maxY) < 0.01)
        let tableRect = fixture.table.convert(fixture.table.bounds, to: clip)
        #expect(abs(tableRect.maxY - clip.bounds.maxY) < 0.01)
        #expect(fixture.document.isAtBottom)
        expectRoomGeometry(fixture.room)
      }
    }
  }

  // The production bridge also leaves sizing to the enclosing layout, not sizeThatFits.
  private struct RoomBridge: NSViewControllerRepresentable {
    let room: ChatRoomContainerView

    func makeNSViewController(context: Context) -> NSViewController {
      let controller = NSViewController()
      controller.view = room
      return controller
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
  }

  @MainActor
  private final class TimelineFixture: NSObject, NSTableViewDataSource {
    let table = TimelineTableView()
    let scroll = NSScrollView()
    let document: TimelineDocumentView
    let room: ChatRoomContainerView
    let rowCount: Int

    init(rowCount: Int) {
      self.rowCount = rowCount
      document = TimelineDocumentView(tableView: table)
      room = ChatRoomContainerView(
        timelineView: scroll, composer: ChatRoomContainerTests().makeComposer())
      super.init()
      table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("test")))
      table.headerView = nil
      table.style = .plain
      table.rowSizeStyle = .custom
      table.rowHeight = 28
      table.intercellSpacing = .zero
      table.usesAutomaticRowHeights = false
      table.dataSource = self
      scroll.borderType = .noBorder
      scroll.hasVerticalScroller = true
      scroll.scrollerStyle = .overlay
      scroll.automaticallyAdjustsContentInsets = false
      scroll.contentInsets = .init()
      scroll.documentView = document
      table.reloadData()
      room.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }

    func layout() {
      room.layoutSubtreeIfNeeded()
      scroll.layoutSubtreeIfNeeded()
      // Mirror TimelineViewController.viewDidLayout after the viewport changes.
      document.updateGeometry()
    }
  }

  private var longReply: EmbeddedEventDetails {
    .error(message: String(repeating: "Long reply content. ", count: 20))
  }

  private func makeRoom() -> ChatRoomContainerView {
    ChatRoomContainerView(timelineView: NSView(), composer: makeComposer())
  }

  private func makeComposer() -> ChatComposerContainer {
    let composer = ChatComposerContainer()
    composer.editor.font = .systemFont(ofSize: 13)
    composer.editor.textContainerInset = DynamicTextView.padding
    composer.editor.isHorizontallyResizable = false
    unsafe composer.editor.textContainer?.widthTracksTextView = true
    return composer
  }

  private func expectRoomGeometry(_ room: ChatRoomContainerView) {
    let bottom = room.bounds.minY + room.safeAreaInsets.bottom
    let availableHeight = max(0, room.bounds.height - room.safeAreaInsets.bottom)
    let composer = room.composer.frame
    let timeline = room.timelineView.frame
    #expect(abs(composer.minX - room.bounds.minX) < 0.01)
    #expect(abs(composer.minY - bottom) < 0.01)
    #expect(abs(composer.width - room.bounds.width) < 0.01)
    #expect(
      abs(composer.height - min(availableHeight, room.composer.height(for: room.bounds.width)))
        < 0.01)
    #expect(abs(timeline.minX - room.bounds.minX) < 0.01)
    #expect(abs(timeline.width - room.bounds.width) < 0.01)
    #expect(timeline.height >= 0)
    #expect(abs(timeline.maxY - room.bounds.maxY) < 0.01)
    #expect(abs(timeline.minY - min(room.bounds.maxY, composer.maxY + 8)) < 0.01)
    if availableHeight >= composer.height + 8 {
      #expect(abs(timeline.minY - composer.maxY - 8) < 0.01)
    }
    #expect(composer.maxY <= room.bounds.maxY + 0.01)
    #expect(timeline.maxY <= room.bounds.maxY + 0.01)
  }

  private func expectComposerContentFits(_ composer: ChatComposerContainer) {
    let editor = composer.editor.convert(composer.editor.bounds, to: composer)
    #expect(abs(editor.minX - 16) < 0.01)
    #expect(abs(editor.maxX - (composer.bounds.width - 16)) < 0.01)
    #expect(abs(editor.minY - 10) < 0.01)
    #expect(
      abs(editor.height - composer.editor.height(for: composer.bounds.width - 32)) < 0.01)
    for view in [composer.editor, composer.reply, composer.attachments] where !view.isHidden {
      let rect = view.convert(view.bounds, to: composer)
      #expect(rect.minX >= -0.01)
      #expect(rect.maxX <= composer.bounds.maxX + 0.01)
      #expect(rect.minY >= -0.01)
      #expect(rect.maxY <= composer.bounds.maxY + 0.01)
    }
    if !composer.attachments.isHidden {
      #expect(abs(composer.attachments.frame.width - (composer.bounds.width - 32)) < 0.01)
      #expect(composer.attachments.documentView!.frame.width >= composer.attachments.bounds.width)
    }
  }

  private func attachment() -> ComposerAttachment {
    ComposerAttachment(
      sourceURL: URL(fileURLWithPath: "/tmp/room-layout-test.pdf"),
      filename: "test.pdf", contentType: .pdf, byteCount: 1, kind: .file,
      storageOwnership: .externalUserFile,
      deduplicationIdentity: .absolutePath("/tmp/room-layout-test.pdf"))
  }
}

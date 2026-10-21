import AppKit
import MactrixUI

@MainActor
enum UserDragging {
  @discardableResult
  static func begin(
    payload: UserDragPayload,
    from view: NSView,
    avatarView: AvatarView,
    font: NSFont = .boldSystemFont(ofSize: NSFont.systemFontSize),
    event: NSEvent,
    source: any NSDraggingSource
  ) throws -> NSDraggingSession? {
    avatarView.layoutSubtreeIfNeeded()

    guard avatarView.bounds.width > 0, avatarView.bounds.height > 0 else { return nil }

    let sourceAvatarFrame = avatarView.convert(avatarView.bounds, to: view)
    let preview = UserDragPreviewView(
      userID: payload.userID,
      username: payload.username,
      avatarView: avatarView,
      avatarSize: sourceAvatarFrame.height,
      font: font
    )
    preview.appearance = view.effectiveAppearance

    guard
      let image = preview.makeDraggingImage(
        backingScaleFactor: view.window?.backingScaleFactor ?? 2
      )
    else { return nil }

    // Keep the preview's avatar centered over the source, including in flipped views.
    let previewFrame = NSRect(
      x: sourceAvatarFrame.midX - preview.avatarFrame.midX,
      y: sourceAvatarFrame.midY - preview.bounds.height / 2,
      width: preview.bounds.width,
      height: preview.bounds.height
    )
    let item = NSDraggingItem(pasteboardWriter: try payload.makePasteboardItem())
    item.setDraggingFrame(previewFrame, contents: image)

    let session = view.beginDraggingSession(with: [item], event: event, source: source)
    session.animatesToStartingPositionsOnCancelOrFail = true
    return session
  }
}

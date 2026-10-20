import AppKit
import Utils

/// Read-only message text with Matrix user links handled in the originating window.
class MessageTextView: NSTextView, NSTextViewDelegate {
  var onFocusUser: ((String) -> Void)?
  private let backingTextStorage: NSTextStorage?

  override init(frame frameRect: NSRect, textContainer container: NSTextContainer? = nil) {
    let resolvedContainer: NSTextContainer
    if let container {
      backingTextStorage = container.layoutManager?.textStorage
      resolvedContainer = container
    } else {
      let storage = NSTextStorage()
      backingTextStorage = storage
      let layoutManager = NSLayoutManager()
      resolvedContainer = NSTextContainer(
        size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
      storage.addLayoutManager(layoutManager)
      layoutManager.addTextContainer(resolvedContainer)
    }
    super.init(frame: frameRect, textContainer: resolvedContainer)
    delegate = self
    isEditable = false
    isSelectable = true
    isRichText = true
    drawsBackground = false
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    textContainer?.heightTracksTextView = false
    textContainer?.containerSize.height = .greatestFiniteMagnitude
    isHorizontallyResizable = false
    isVerticallyResizable = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL,
      let uri = (try? MatrixUriScheme(parseUrl: url.absoluteString))
        ?? (try? MatrixUriScheme(parseMatrixToUrl: url.absoluteString)),
      case .user(let userId) = uri.kind, uri.action == nil,
      let onFocusUser
    else { return false }

    onFocusUser(userId)
    return true
  }
}

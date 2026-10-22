import AppKit
import Utils

/// NSTextView with Matrix user links handled in the originating window.
/// Shares read-only message styling.
class MessageTextView: NSTextView, NSTextViewDelegate {
  var handleMatrixUri: ((MatrixUriScheme) -> Bool)?

  override init(frame frameRect: NSRect) {
    // Preserve AppKit's default TextKit graph and sizing, just like NSTextView(frame:).
    super.init(frame: frameRect)
    configure()
  }

  override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    configure()
  }

  private func configure() {
    delegate = self
    isEditable = false
    isSelectable = true
    isRichText = true
    drawsBackground = false
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    isHorizontallyResizable = false
    translatesAutoresizingMaskIntoConstraints = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL,
      let uri = (try? MatrixUriScheme(parseUrl: url.absoluteString))
        ?? (try? MatrixUriScheme(parseMatrixToUrl: url.absoluteString))
    else { return false }

    return handleMatrixUri?(uri) ?? false
  }
}

import AppKit
import MactrixUI

class DynamicTextView: SubmitableTextView {
  @objc var placeholderAttributedString: NSAttributedString?

  static let padding = NSSize(width: 10, height: 10)

  var attachmentDropDestination: ComposerAttachmentDropDestination?
  private var isInterceptingAttachmentDrag = false
  var onWindowChanged: (() -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChanged?()
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    isInterceptingAttachmentDrag = attachmentDropDestination?.recognizes(sender) == true
    if isInterceptingAttachmentDrag {
      return attachmentDropDestination?.entered(sender) ?? []
    }
    return super.draggingEntered(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    isInterceptingAttachmentDrag = attachmentDropDestination?.recognizes(sender) == true
    if isInterceptingAttachmentDrag {
      return attachmentDropDestination?.entered(sender) ?? []
    }
    return super.draggingUpdated(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    attachmentDropDestination?.exited()
    if !isInterceptingAttachmentDrag { super.draggingExited(sender) }
    isInterceptingAttachmentDrag = false
  }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if attachmentDropDestination?.recognizes(sender) == true {
      return attachmentDropDestination?.operation(sender) == .copy
    }
    return super.prepareForDragOperation(sender)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if attachmentDropDestination?.recognizes(sender) == true {
      return attachmentDropDestination?.perform(sender) ?? false
    }
    return super.performDragOperation(sender)
  }

  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    attachmentDropDestination?.exited()
    if !isInterceptingAttachmentDrag {
      super.concludeDragOperation(sender)
      window?.makeFirstResponder(self)
    }
    isInterceptingAttachmentDrag = false
  }

  var onCanPasteAttachments: ((NSPasteboard) -> Bool)?
  var onAttachmentPaste: ((NSPasteboard) -> Bool)?

  override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
    [.mactrixUser, .string]
  }

  override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
    readablePasteboardTypes
      + (attachmentDropDestination == nil ? [] : ComposerAttachmentInputAdapter.dragTypes)
  }

  override func readSelection(
    from pasteboard: NSPasteboard,
    type: NSPasteboard.PasteboardType
  ) -> Bool {
    guard type == .mactrixUser else {
      return super.readSelection(from: pasteboard, type: type)
    }

    guard isEditable,
      let payload = UserDragPayload.read(from: pasteboard)
    else {
      return false
    }

    insertText(payload.markdownLink ?? payload.userId, replacementRange: selectedRange())
    return true
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(paste(_:)) {
      guard isEditable else { return false }
      if onAttachmentPaste != nil, onCanPasteAttachments?(NSPasteboard.general) == true {
        return true
      }
    }
    return super.validateUserInterfaceItem(item)
  }

  override func paste(_ sender: Any?) {
    guard isEditable else { return }
    if onAttachmentPaste?(NSPasteboard.general) != true {
      super.paste(sender)
    }
  }

  func height(for width: CGFloat) -> CGFloat {
    guard let liveContainer = unsafe textContainer, let storage = unsafe textStorage else {
      return 0
    }

    // SwiftUI can measure proposals that never become the view's actual width.
    // Use a separate layout so probes cannot change the editor's wrapping or frame.
    let measurementStorage = NSTextStorage(attributedString: storage)
    let manager = NSLayoutManager()
    let container = NSTextContainer(
      containerSize: NSSize(
        width: max(width - 2 * textContainerInset.width, 1),
        height: .greatestFiniteMagnitude))

    container.lineFragmentPadding = liveContainer.lineFragmentPadding
    measurementStorage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.ensureLayout(for: container)

    let lineHeight = manager.defaultLineHeight(for: font ?? .systemFont(ofSize: 13))
    let textHeight = max(
      lineHeight,
      max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY))

    return ceil(textHeight + 2 * textContainerInset.height)
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: height(for: frame.width))
  }

  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = frame.width
    super.setFrameSize(newSize)

    if oldWidth != newSize.width {
      invalidateIntrinsicContentSize()
    }
  }

  override func didChangeText() {
    super.didChangeText()
    invalidateIntrinsicContentSize()
  }

}

class SubmitableTextView: NSTextView {
  var onSubmit: (() -> Void)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // Always submit on cmd+enter
    if (event.specialKey == .enter || event.specialKey == .carriageReturn)
      && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command]
    {
      onSubmit?()
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    // Handle enter as submit instead of newline
    if event.specialKey == .enter || event.specialKey == .carriageReturn,
      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == []
    {
      onSubmit?()
      return
    }

    super.keyDown(with: event)
  }
}

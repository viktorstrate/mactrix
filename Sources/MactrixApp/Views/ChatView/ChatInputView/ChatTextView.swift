import AppKit
import OSLog
import SwiftUI

struct ChatTextView: NSViewRepresentable {
  typealias NSViewRepresentableType = NSTextView

  @AppStorage("fontSize") var fontSize: Int = 13

  let text: Binding<String>
  let placeholder: String
  let disabled: Bool
  let focusRequest: Int
  let onSubmit: () -> Void
  let onAttachmentPaste: (NSPasteboard) -> Bool

  func makeNSView(context: Context) -> DynamicTextView {
    let textView = DynamicTextView()

    textView.onSubmit = onSubmit
    textView.onAttachmentPaste = onAttachmentPaste

    textView.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .foregroundColor: NSColor.secondaryLabelColor,
        .font: NSFont.systemFont(ofSize: CGFloat(fontSize)),
      ]
    )

    textView.backgroundColor = .clear
    textView.drawsBackground = false

    context.coordinator.textView = textView
    textView.delegate = context.coordinator

    textView.textContainerInset = DynamicTextView.padding

    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    unsafe textView.textContainer?.widthTracksTextView = true

    textView.setContentHuggingPriority(.required, for: .vertical)
    textView.setContentCompressionResistancePriority(.required, for: .vertical)

    textView.font = NSFont.systemFont(ofSize: CGFloat(fontSize))

    return textView
  }

  func updateNSView(_ textView: DynamicTextView, context: Context) {
    context.coordinator.text = text

    textView.onSubmit = onSubmit
    textView.onAttachmentPaste = onAttachmentPaste

    if textView.string != text.wrappedValue {
      textView.string = text.wrappedValue
      textView.invalidateIntrinsicContentSize()
    }

    let currentPlaceholderFont =
      unsafe textView.placeholderAttributedString?
      .attribute(
        .font,
        at: 0,
        effectiveRange: nil
      ) as? NSFont
    let placeholderFontChanged =
      currentPlaceholderFont?.pointSize != CGFloat(fontSize)
    if textView.placeholderAttributedString?.string != placeholder || placeholderFontChanged {
      textView.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
          .foregroundColor: NSColor.secondaryLabelColor,
          .font: NSFont.systemFont(ofSize: CGFloat(fontSize)),
        ]
      )
    }

    if textView.isEditable != !disabled {
      textView.isEditable = !disabled
      textView.isSelectable = !disabled
      textView.alphaValue = !disabled ? 1.0 : 0.5

      if disabled {
        // resign first responder
        unsafe textView.window?.makeFirstResponder(nil)
      }
    }

    context.coordinator.requestFocus(focusRequest, disabled: disabled)

    let currentFont = NSFont.systemFont(ofSize: CGFloat(fontSize))
    if textView.font?.pointSize != currentFont.pointSize {
      textView.font = currentFont
      textView.invalidateIntrinsicContentSize()
    }
  }

  func makeCoordinator() -> Coordinator {
    return Coordinator(text: text)
  }

  @MainActor
  class Coordinator: NSObject, NSTextViewDelegate {
    var textView: NSTextView?
    var text: Binding<String>
    private var requestedFocus = 0
    private var fulfilledFocus = 0

    init(text: Binding<String>) {
      self.text = text
    }

    func requestFocus(_ request: Int, disabled: Bool) {
      requestedFocus = request
      guard !disabled, request != fulfilledFocus else { return }

      Task { @MainActor [weak self] in
        await Task.yield()
        guard let self, requestedFocus == request, let textView, textView.isEditable,
          let window = textView.window
        else { return }

        if window.makeFirstResponder(textView) {
          fulfilledFocus = request
        }
      }
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }

      text.wrappedValue = textView.string
    }
  }
}

class DynamicTextView: NSTextView {
  @objc var placeholderAttributedString: NSAttributedString?

  static let padding = NSSize(width: 10, height: 10)

  var onSubmit: (() -> Void)?
  var onAttachmentPaste: ((NSPasteboard) -> Bool)?

  override func paste(_ sender: Any?) {
    if onAttachmentPaste?(NSPasteboard.general) != true {
      super.paste(sender)
    }
  }

  override var intrinsicContentSize: NSSize {
    guard let container = unsafe textContainer, let manager = unsafe layoutManager else {
      return .zero
    }

    // Force the layout for the current width
    manager.ensureLayout(for: container)
    let usedRect = manager.usedRect(for: container)

    // Return a flexible width but a fixed height based on text
    return NSSize(
      width: NSView.noIntrinsicMetric,
      height: ceil(usedRect.height) + CGFloat(2 * Self.padding.height))
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

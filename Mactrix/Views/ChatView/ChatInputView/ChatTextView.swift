import AppKit
import OSLog
import SwiftUI

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView
    
    let text: Binding<String>
    let placeholder: String
    let disabled: Bool
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> DynamicTextView {
        let textView = DynamicTextView()
        
        textView.onSubmit = onSubmit
        
        textView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
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
        
        return textView
    }
    
    func updateNSView(_ textView: DynamicTextView, context: Context) {
        context.coordinator.text = text
        
        textView.onSubmit = onSubmit
        
        if textView.string != text.wrappedValue {
            textView.string = text.wrappedValue
            textView.invalidateIntrinsicContentSize()
        }
        
        if textView.placeholderAttributedString?.string != placeholder {
            textView.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
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
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(text: text)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
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
    
    override var intrinsicContentSize: NSSize {
        guard let container = unsafe textContainer, let manager = unsafe layoutManager else {
            return .zero
        }
        
        // Force the layout for the current width
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)
        
        // Return a flexible width but a fixed height based on text
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height) + CGFloat(2 * Self.padding.height))
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

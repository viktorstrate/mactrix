import AppKit
import OSLog
import SwiftUI

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView
    
    let text: Binding<String>
    let disabled: Bool
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = DynamicTextView()
        
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        
        textView.textContainerInset = NSSize(width: DynamicTextView.padding, height: DynamicTextView.padding)
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        unsafe textView.textContainer?.widthTracksTextView = true
        
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        return textView
    }
    
    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.text = text
        
        if textView.string != text.wrappedValue {
            textView.string = text.wrappedValue
            textView.invalidateIntrinsicContentSize()
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
    static let padding = 4
    
    override var intrinsicContentSize: NSSize {
        guard let container = unsafe textContainer, let manager = unsafe layoutManager else {
            return .zero
        }
        
        // Force the layout for the current width
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)
        
        // Return a flexible width but a fixed height based on text
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height) + CGFloat(2 * Self.padding))
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

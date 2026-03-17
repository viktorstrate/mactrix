import AppKit
import OSLog
import SwiftUI

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView
    
    let text: Binding<String>
    let disabled: Bool
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.text = text
        
        if textView.string != text.wrappedValue {
            textView.string = text.wrappedValue
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
                
            // Make SwiftUI call sizeThatFits when the text changes
            // textView.invalidateIntrinsicContentSize()
        }
    }
    
    /* func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
         guard let container = unsafe textView.textContainer,
               let layoutManager = unsafe textView.layoutManager else { return nil }
         guard let width = proposal.width, width > 0 else { return nil }

         // Set the container width to the proposed width to force correct wrapping
         container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
         layoutManager.ensureLayout(for: container)
                
         let usedRect = layoutManager.usedRect(for: container)
         let size = usedRect.size
         //let size = CGSize(width: width, height: usedRect.height)
         Logger.chatTextView.debug("Size of input view: \(size.width)x\(size.height), proposed width: \(width)")
         return size
     } */
}

// MARK: - Subclass for Intrinsic Sizing

class DynamicTextView: NSTextView {
    // We override this so AppKit/SwiftUI knows our true height requirement
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return .zero
        }
        
        // Force the layout for the current width
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)
        
        // Return a flexible width but a fixed height based on text
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }
    
    // Crucial: When the width changes (window resize), we must re-calculate height
    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        
        if oldWidth != newSize.width {
            invalidateIntrinsicContentSize()
        }
    }
}

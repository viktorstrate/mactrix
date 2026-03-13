import AppKit
import SwiftUI

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        
        textView.delegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {}
}

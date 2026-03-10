import SwiftUI

public struct AttributedTextView: NSViewRepresentable {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }

    public func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(labelWithAttributedString: attributedString)

        // Behavior settings
        textField.isEditable = false
        textField.isSelectable = true
        textField.allowsEditingTextAttributes = true

        // Enable text wrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.lineBreakStrategy = .standard
        textField.lineBreakMode = .byWordWrapping

        // Layout Priority, this helps SwiftUI understand it should stretch vertically
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        return textField
    }

    public func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.attributedStringValue != attributedString {
            textField.attributedStringValue = attributedString
        }
    }
}

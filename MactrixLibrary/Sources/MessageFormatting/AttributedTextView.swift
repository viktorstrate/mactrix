import SwiftUI

public struct AttributedTextView: NSViewRepresentable {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }

    public func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(labelWithAttributedString: attributedString)

        textField.isEditable = false
        textField.isSelectable = true
        textField.allowsEditingTextAttributes = true

        textField.lineBreakStrategy = .standard
        textField.lineBreakMode = .byWordWrapping
        textField.usesSingleLineMode = false

        return textField
    }

    public func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.attributedStringValue != attributedString {
            textField.attributedStringValue = attributedString
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width != .infinity else { return nil }

        textField.preferredMaxLayoutWidth = width
        return textField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude))
    }
}

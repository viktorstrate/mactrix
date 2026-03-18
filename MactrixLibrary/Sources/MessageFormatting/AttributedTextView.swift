import SwiftUI

public struct AttributedTextView: NSViewRepresentable {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString.trimmed
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
        guard let size = textField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)) else {
            return nil
        }
        
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

extension NSAttributedString {
    var trimmed: NSAttributedString {
        let nonWhitespaces = CharacterSet.whitespacesAndNewlines.inverted
        let startRange = string.rangeOfCharacter(from: nonWhitespaces)
        let endRange = string.rangeOfCharacter(from: nonWhitespaces, options: .backwards)
        guard let startLocation = startRange?.upperBound, let endLocation = endRange?.lowerBound else {
            return self
        }
        let location = string.distance(from: string.startIndex, to: startLocation) - 1
        let length = string.distance(from: startLocation, to: endLocation) + 2
        let range = NSRange(location: location, length: length)

        return attributedSubstring(from: range)
    }
}

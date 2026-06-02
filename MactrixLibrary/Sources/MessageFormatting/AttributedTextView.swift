import SwiftUI

public struct AttributedTextView: NSViewRepresentable {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString.trimmed
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.focusRingType = .none

        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false

        textView.textStorage?.setAttributedString(attributedString)

        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.attributedString() != attributedString {
            textView.textStorage?.setAttributedString(attributedString)
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width != .infinity else { return nil }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
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

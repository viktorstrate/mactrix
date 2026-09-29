import Foundation

public extension String {
    var formatAsMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let formattedString = try? AttributedString(markdown: self, options: options) {
            return formattedString
        } else {
            return AttributedString(self)
        }
    }
}

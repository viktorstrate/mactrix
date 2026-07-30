import MatrixRustSDK
import MessageFormatting
import SwiftUI

struct FormattedBodyView: View {
    @AppStorage("fontSize") private var fontSize = 13
    
    let rawBody: String
	var formattedBody: NSAttributedString? = nil
	var color: NSColor? = nil
    
	init(messageContent: some MessageContent) {
		self.rawBody = messageContent.body
		
		if let formatted = messageContent.formatted, formatted.format == .html {
			self.formattedBody = parseFormattedBody(formatted.body, baseFontSize: CGFloat(fontSize))
		}
	}
	
	// accepts a custom foreground color (for use in grayed out messages)
	init(messageContent: some MessageContent, color: NSColor) {
        self.rawBody = messageContent.body
		self.color = color
        
		if let formatted = messageContent.formatted, formatted.format == .html {
			let parsed = parseFormattedBody(formatted.body, baseFontSize: CGFloat(fontSize))
			
			let mutable = NSMutableAttributedString(attributedString: parsed)
			mutable.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutable.length))
			
			self.formattedBody = mutable
        }
    }
    
    var body: some View {
        if let formattedBody {
            AttributedTextView(attributedString: formattedBody)
                .fixedSize(horizontal: false, vertical: true)
        } else if let color {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
				.foregroundStyle(Color(nsColor: color))
		} else {
			Text(rawBody)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
		}
    }
}

import MatrixRustSDK
import MessageFormatting
import SwiftUI

struct FormattedBodyView: View {
    @AppStorage("fontSize") private var fontSize = 13
    
    let rawBody: String
    var formattedBody: AttributedString? = nil
    
    init(messageContent: some MessageContent) {
        self.rawBody = messageContent.body
        
        if let formatted = messageContent.formatted, formatted.format == .html {
			let parsed = parseFormattedBody(formatted.body, baseFontSize: CGFloat(fontSize))
			self.formattedBody = AttributedString(parsed.trimmed)
        }
    }
    
    var body: some View {
        if let formattedBody {
			Text(formattedBody)
				.textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

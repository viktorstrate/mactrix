import Models
import SwiftUI

public enum SessionVerificationResponse {
    case accept, decline
}

public struct SessionVerificationModal<VerificationEmoji: SessionVerificationEmoji>: View {
    let verificationData: SessionVerificationData<VerificationEmoji>
    var onComplete: (_ response: SessionVerificationResponse) -> Void

    @Environment(\.dismiss) var dismiss

    public init(verificationData: SessionVerificationData<VerificationEmoji>, onComplete: @escaping (_ response: SessionVerificationResponse) -> Void) {
        self.verificationData = verificationData
        self.onComplete = onComplete
    }

    var subtitle: String {
        switch verificationData {
        case .emojis(emojis: _, indices: _):
            "Do the emojis match with the other device?"
        case .decimals(values: _):
            "Do the numbers match with the other device?"
        }
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text("Session Verification")
                    .font(.title)

                Text(subtitle)
            }

            switch verificationData {
            case let .emojis(emojis, _):
                HStack(spacing: 20) {
                    ForEach(emojis) { emoji in
                        VStack {
                            Text(emoji.symbol)
                                .font(.system(size: 32))
                            Text(emoji.description)
                                .font(.caption)
                        }
                    }
                }

            case let .decimals(values):
                ForEach(values, id: \.self) { value in
                    Text("\(value)")
                }
            }

            HStack {
                Button("They match") { onComplete(.accept) }
                    .buttonStyle(.borderedProminent)

                Button("They don't match") { onComplete(.decline) }
            }
        }
        .padding()
    }
}

#Preview {
    let data = SessionVerificationData.emojis(emojis: [
        MockSessionVerificationEmoji(description: "smiling", symbol: "😄"),
        MockSessionVerificationEmoji(description: "dog", symbol: "🐶"),
        MockSessionVerificationEmoji(description: "rocket", symbol: "🚀"),
        MockSessionVerificationEmoji(description: "fish", symbol: "🐠"),
        MockSessionVerificationEmoji(description: "butterfly", symbol: "🦋"),
        MockSessionVerificationEmoji(description: "rose", symbol: "🌹"),
        MockSessionVerificationEmoji(description: "sun", symbol: "☀️"),
    ], indices: Data())

    SessionVerificationModal(verificationData: data, onComplete: { _ in })
}

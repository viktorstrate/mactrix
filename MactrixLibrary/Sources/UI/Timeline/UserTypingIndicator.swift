import SwiftUI

public struct UserTypingIndicator: View {
    let names: [String]

    public init(names: [String]) {
        self.names = names
    }

    var namesFormattedText: AttributedString {
        var result = AttributedString()

        var namesFormatted = AttributedString(names.joined(separator: ", "))
        namesFormatted.font = .body.bold()

        result.append(namesFormatted)

        if names.count == 1 {
            result.append(AttributedString(localized: " is typing"))
        } else {
            result.append(AttributedString(localized: " are typing"))
        }

        return result
    }

    @ViewBuilder
    var dots: some View {
        let dotSize: CGFloat = 6

        KeyframeAnimator(initialValue: -3.0, repeating: true) { stage in
            HStack(spacing: 2) {
                ForEach(0 ..< 3, id: \.self) { i in
                    Circle()
                        .frame(width: dotSize, height: dotSize)
                        .opacity(max(1.0 - (stage - Double(i)).magnitude / 6.0, 0.5) - 0.3)
                        .scaleEffect(max(1.0 - (stage - Double(i)).magnitude / 7.0, 0.9))
                }
            }
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(6.0, duration: 1.8)
            }
        }
    }

    public var body: some View {
        HStack {
            dots
            Text(namesFormattedText)
        }
        .opacity(names.isEmpty ? 0 : 1)
    }
}

#Preview {
    VStack(alignment: .leading) {
        UserTypingIndicator(names: ["John Doe"])
        UserTypingIndicator(names: ["John Doe", "Person"])
        UserTypingIndicator(names: [])
    }
    .padding()
}

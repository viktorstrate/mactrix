import Foundation

public enum SessionVerificationData<VerificationEmoji: SessionVerificationEmoji> {
    case emojis(emojis: [VerificationEmoji], indices: Data)
    case decimals(values: [UInt16])
}

public protocol SessionVerificationEmoji: Identifiable {
    var description: String { get }
    var symbol: String { get }
}

public struct MockSessionVerificationEmoji: SessionVerificationEmoji {
    public var id: String { symbol }

    public var description: String
    public var symbol: String

    public init(description: String, symbol: String) {
        self.description = description
        self.symbol = symbol
    }
}

public protocol ThreadSummary {
    func numReplies() -> UInt64

    var description: String? { get }
}

public struct MockThreadSummary: ThreadSummary {
    public init() {}

    public func numReplies() -> UInt64 {
        4
    }

    public var description: String? {
        """
        This is a thread message, that is _very_ long.

        It event has multiple lines.
        """
    }
}

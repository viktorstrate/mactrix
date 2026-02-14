import Foundation
import MatrixRustSDK
import OSLog

@MainActor
final class MatrixRustListener<Element: Sendable> {
    private var taskHandle: TaskHandle?
    private var task: Task<Void, Never>?

    init(
        configure: @escaping (AsyncStream<Element>.Continuation) async -> TaskHandle?,
        onElement: @MainActor @escaping (Element) async -> Void) async
    {
        let (stream, continuation) = AsyncStream<Element>.makeStream()

        taskHandle = await configure(continuation)

        task = Task {
            for await element in stream {
                await onElement(element)
            }
        }
    }

    deinit {
        task?.cancel()
        task = nil
        taskHandle?.cancel()
        taskHandle = nil
    }
}

final class AsyncSDKListener<Element: Sendable>: AsyncSequence, Sendable {
    typealias Element = Element
    typealias AsyncIterator = AsyncStream<Element>.Iterator

    private let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation

    init() {
        let (s, c) = AsyncStream<Element>.makeStream()
        stream = s
        continuation = c
    }

    func onUpdate(_ element: Element) {
        continuation.yield(element)
    }

    func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        let s = AsyncStream<Element> { _ in }
        return s.makeAsyncIterator()
    }
}

extension AsyncSDKListener: TypingNotificationsListener where Element == [String] {
    func call(typingUserIds: [String]) {
        Logger.matrixClient.info("typing indicator called from rust")
        onUpdate(typingUserIds)
    }
}

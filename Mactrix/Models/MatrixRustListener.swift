import Foundation
import MatrixRustSDK

@MainActor
final class MatrixRustListener<Element: Sendable> {
    private var taskHandle: TaskHandle?
    private var task: Task<Void, Never>?

    init(
        configure: @escaping (AsyncStream<Element>.Continuation) async -> TaskHandle,
        onElement: @escaping (Element) -> Void)
    {
        let (stream, continuation) = AsyncStream<Element>.makeStream()

        Task {
            self.taskHandle = await configure(continuation)
        }

        task = Task { [weak self] in
            for await element in stream {
                guard let self else { break }
                onElement(element)
            }
        }
    }

    deinit {
        task?.cancel()
        task = nil
    }
}

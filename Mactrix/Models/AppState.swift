import Foundation
import MatrixRustSDK
import Models

@MainActor
@Observable final class AppState {
    var matrixClient: MatrixClient?

    func reset() async throws {
        do {
            try await matrixClient?.reset()
        } catch {
            print("Failed to reset matrix client: \(error)")
        }
        matrixClient = nil
    }
}

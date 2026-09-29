import Foundation
import MatrixRustSDK
import MatrixProtocols
import OSLog

@MainActor @Observable
final class AppState {
    var matrixClient: MatrixClient?

    func reset() async throws {
        do {
            try await matrixClient?.reset()
        } catch {
            Logger.viewCycle.error("Failed to reset matrix client: \(error)")
        }
        matrixClient = nil
    }
}

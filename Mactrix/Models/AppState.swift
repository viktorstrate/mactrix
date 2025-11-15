import Foundation
import Models
import MatrixRustSDK

@MainActor
@Observable final class AppState {
    var matrixClient: MatrixClient? = nil
    
    func reset() async throws {
        do {
            try await self.matrixClient?.reset()
        } catch {
            print("Failed to reset matrix client: \(error)")
        }
        matrixClient = nil
    }
    
    static var previewMock: AppState {
        let appState = AppState()
        appState.matrixClient = .previewMock
        
        return appState
    }
}

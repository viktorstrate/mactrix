import SwiftUI
import MatrixRustSDK

struct AccountSettingsView: View {
    @Environment(AppState.self) var appState
    
    @State private var logoutError: String? = nil
    
    var body: some View {
        if let matrixClient = appState.matrixClient {
            Form {
                LabeledContent("User") {
                    Text((try? matrixClient.client.userId()) ?? "error")
                        .textSelection(.enabled)
                }
                
                LabeledContent("Device") {
                    Text((try? matrixClient.client.deviceId()) ?? "error")
                        .textSelection(.enabled)
                }
                
                HStack {
                    Button("Sign out", role: .destructive) {
                        Task {
                            do {
                                try await appState.reset()
                            } catch {
                                logoutError = error.localizedDescription
                            }
                        }
                    }
                    if let logoutError = logoutError {
                        Text(logoutError)
                            .textSelection(.enabled)
                            .foregroundStyle(Color.red)
                    }
                }
                
                Button("Clear cache") {
                    Task {
                        try await appState.matrixClient?.clearCache()
                    }
                }
            }
        } else {
            ContentUnavailableView("User not logged in", systemImage: "person")
        }
    }
}

#Preview {
    AccountSettingsView()
}

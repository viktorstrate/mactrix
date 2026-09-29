import MatrixRustSDK
import OSLog
import SwiftUI

struct SidebarSyncStateView: View {
    @Environment(AppState.self) var appState

    @State var restarting: Bool = false

    var syncState: String {
        switch appState.matrixClient?.syncState {
        case .idle:
            "idle"
        case .running:
            "online"
        case .terminated:
            "terminated"
        case .error:
            "error"
        case .offline:
            "offline"
        case nil:
            "logged out"
        }
    }

    var canRestart: Bool {
        return [.error, .offline, .terminated].contains(where: { $0 == appState.matrixClient?.syncState })
    }

    var body: some View {
        VStack {
            Text("Sync: \(syncState)")
                .foregroundStyle(.secondary)
            if canRestart {
                Button("Restart sync") {
                    Task {
                        restarting = true
                        defer { restarting = false }

                        do {
                            try await appState.matrixClient?.startSync()
                        } catch {
                            Logger.viewCycle.error("failed to restart sync: \(error)")
                        }
                    }
                }
                .disabled(restarting)
            }
        }
    }
}

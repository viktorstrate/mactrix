import MatrixRustSDK
import OSLog
import SwiftUI

struct SessionVerificationStatusView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder
    var selfVerificationView: some View {
        switch appState.matrixClient?.verificationState {
        case nil:
            EmptyView()
        case .unknown:
            Text("Unknown verification state")
                .padding(10)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
        case .verified:
            EmptyView()
        case .unverified:
            VStack {
                Label("Unverified session", systemImage: "exclamationmark.shield")
                    .frame(maxWidth: .infinity)
                Button("Verify session") {
                    Task {
                        do {
                            try await appState.matrixClient?.requestDeviceVerification()
                        } catch {
                            Logger.viewCycle.error("request device verification failed: \(error)")
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.red.opacity(0.2))
            .foregroundStyle(Color.red.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var body: some View {
        if let verificationRequest = appState.matrixClient?.sessionVerificationRequest {
            VStack {
                Label("Verification request from \(verificationRequest.senderProfile.userId)", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
                HStack {
                    Button("Start Verification") {
                        Task {
                            do {
                                try await appState.matrixClient?.acceptVerificationRequest(request: verificationRequest)
                            } catch {
                                Logger.viewCycle.error("failed to accept verification request: \(error)")
                                appState.matrixClient?.sessionVerificationRequest = nil
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Decline") {
                        Task {
                            do {
                                try await appState.matrixClient?.declineVerificationRequest(request: verificationRequest)
                            } catch {
                                Logger.viewCycle.error("failed to decline verification request: \(error)")
                                appState.matrixClient?.sessionVerificationRequest = nil
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.2))
            .foregroundStyle(Color.green.mix(with: .black, by: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            selfVerificationView
        }
    }
}

import MatrixRustSDK
import OSLog
import SwiftUI

struct SessionVerificationStatusView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
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
                Label {
                    Text("This session is unverified.")
                        .bold()

                    // NOTE(alicerunsonfedora): Setting a hard line limit because SwiftUI will otherwise truncate the
                    // text, even when there's enough room to do so.
                    Text("Verify the session for better security and to decrypt all messages.")
                        .lineLimit(9)
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .bold()
                }
                .labelStyle(.multiline)
                .frame(maxWidth: .infinity)
                HStack {
                    if windowState.requestedVerification {
                        ProgressView("Requesting verification from your trusted devices...")
                    }
                    Button(windowState.requestedVerification ? "Try again" : "Verify session...") {
                        Task {
                            await startVerificationRequest()
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

    private func startVerificationRequest() async {
        do {
            try await appState.matrixClient?.requestDeviceVerification()
            windowState.requestedVerification = true
        } catch {
            Logger.viewCycle.error("request device verification failed: \(error)")
        }
    }
}

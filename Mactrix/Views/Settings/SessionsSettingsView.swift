import MatrixRustSDK
import SwiftUI

struct SessionsSettingsView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder
    func sessionBadge(systemIcon: String, color: Color) -> some View {
        Image(systemName: systemIcon)
            .font(.system(size: 20))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.2)))
            .foregroundStyle(color.mix(with: colorScheme == .light ? .black : .white, by: 0.2))
    }

    @ViewBuilder
    func sessionVerificationState(badge: some View, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack {
            badge
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title3)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    func sessionVerificationView(matrixClient: MatrixClient) -> some View {
        switch matrixClient.verificationState {
        case nil, .unknown:
            sessionVerificationState(
                badge: sessionBadge(systemIcon: "shield.fill", color: .gray),
                title: "Session verification is unknown",
                subtitle: "The information could not be retrieved."
            )
        case .verified:
            sessionVerificationState(
                badge: sessionBadge(systemIcon: "checkmark.shield.fill", color: .green),
                title: "Verified session",
                subtitle: "This session is verified and ready for secure messaging."
            )
        case .unverified:
            sessionVerificationState(
                badge: sessionBadge(systemIcon: "xmark.shield.fill", color: .red),
                title: "Unverified session",
                subtitle: "Verify the session for better security and to decrypt all messages."
            )
        }
    }

    var body: some View {
        if let matrixClient = appState.matrixClient {
            sessionVerificationView(matrixClient: matrixClient)
        } else {
            ContentUnavailableView("User not logged in", systemImage: "person")
        }
    }
}

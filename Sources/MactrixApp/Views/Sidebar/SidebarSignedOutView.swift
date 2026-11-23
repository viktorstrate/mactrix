import OSLog
import SwiftUI

/// Shown when the server has ended the active account's session.
struct SidebarSignedOutView: View {
  @Environment(AppState.self) var appState
  @Environment(\.colorScheme) var colorScheme

  @State private var signingOut = false

  var body: some View {
    if let matrixClient = appState.matrixClient, matrixClient.authenticationFailed {
      VStack {
        Label {
          Text("You were signed out.")
            .bold()
          Text("This session was ended by the server or another device.")
            .lineLimit(9)
        } icon: {
          Image(systemName: "person.crop.circle.badge.exclamationmark")
            .bold()
        }
        .labelStyle(.multiline)
        .frame(maxWidth: .infinity)

        Button("Sign In Again…") {
          Task {
            signingOut = true
            defer { signingOut = false }
            do {
              try await appState.reset()
            } catch {
              Logger.viewCycle.error("Failed to remove signed out account: \(error)")
            }
          }
        }
        .disabled(signingOut)
      }
      .padding(10)
      .background(Color.orange.opacity(0.2))
      .foregroundStyle(Color.orange.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

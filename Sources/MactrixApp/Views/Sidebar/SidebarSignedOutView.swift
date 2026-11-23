import SwiftUI

/// Shown when the server has ended the active account's session.
struct SidebarSignedOutView: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState
  @Environment(\.colorScheme) var colorScheme

  @State private var removing = false

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

        HStack {
          Button("Sign In Again…") {
            windowState.loginSheet = .signInAgain(userID: matrixClient.userID)
          }
          Button("Remove Account") {
            Task {
              removing = true
              defer { removing = false }
              await appState.remove(matrixClient)
            }
          }
        }
        .disabled(removing)
      }
      .padding(10)
      .background(Color.orange.opacity(0.2))
      .foregroundStyle(Color.orange.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

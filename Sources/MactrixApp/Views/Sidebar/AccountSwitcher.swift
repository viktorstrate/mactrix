import MactrixUI
import MatrixIntegration
import SwiftUI

extension MatrixClient {
  /// The name shown for this account in account lists.
  var accountName: String {
    ownDisplayName ?? userID
  }
}

/// The active account's avatar and name.
struct AccountLabel: View {
  let account: MatrixClient
  var showsUserID = true

  var body: some View {
    HStack(spacing: 8) {
      AvatarImage(
        userID: account.userID, kind: .user, displayName: account.ownDisplayName,
        avatarUrl: account.ownAvatarUrl, imageLoader: account)
      VStack(alignment: .leading, spacing: 0) {
        Text(account.accountName)
          .lineLimit(1)
        if showsUserID, account.ownDisplayName != nil {
          Text(account.userID)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }
}

/// A menu at the top of the sidebar for switching, adding, and signing out of accounts.
struct AccountSwitcher: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  @State private var accountToSignOut: MatrixClient?

  var body: some View {
    Menu {
      ForEach(appState.accounts, id: \.storeID) { account in
        Toggle(
          isOn: Binding(
            get: { appState.activeAccountID == account.storeID },
            set: { if $0 { appState.activate(account) } })
        ) {
          Text(menuTitle(for: account))
        }
      }

      Divider()

      Button("Add Account…") {
        windowState.loginSheet = .addAccount
      }

      if let active = appState.matrixClient {
        Button("Sign Out of \(active.accountName)…") {
          accountToSignOut = active
        }
      }
    } label: {
      if let active = appState.matrixClient {
        AccountLabel(account: active)
      } else {
        Text("No Account")
      }
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.visible)
    .fixedSize(horizontal: false, vertical: true)
    .help("Switch account")
    .confirmationDialog(
      "Sign out of \(accountToSignOut?.accountName ?? "")?",
      isPresented: Binding(
        get: { accountToSignOut != nil },
        set: { if !$0 { accountToSignOut = nil } }),
      presenting: accountToSignOut
    ) { account in
      Button("Sign Out", role: .destructive) {
        Task { await appState.remove(account) }
      }
    } message: { account in
      Text("\(account.userID) will be signed out on this Mac. Your other accounts stay signed in.")
    }
  }

  private func menuTitle(for account: MatrixClient) -> String {
    var title = account.accountName
    if account.ownDisplayName != nil {
      title += " (\(account.userID))"
    }
    if account.authenticationFailed {
      title += " — Signed Out"
    } else if account.unreadRoomCount > 0 {
      title += " — \(account.unreadRoomCount) unread"
    }
    return title
  }
}

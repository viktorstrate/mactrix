import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

extension MatrixClient {
  /// The primary name shown for this account: its display name, or its Matrix ID.
  var accountName: String {
    ownDisplayName ?? userID
  }

  /// A one-line title that always includes the Matrix ID, since display names aren't unique.
  var accountMenuTitle: String {
    ownDisplayName.map { "\($0) — \(userID)" } ?? userID
  }
}

/// An account's avatar with its sync state, display name, and Matrix ID.
struct AccountLabel: View {
  let account: MatrixClient
  var showsUserID = true
  var avatarSize: CGFloat = 28

  var body: some View {
    HStack(spacing: 8) {
      AvatarImage(
        userID: account.userID, kind: .user, displayName: account.ownDisplayName,
        avatarUrl: account.ownAvatarUrl, imageLoader: account
      )
      .frame(width: avatarSize, height: avatarSize)
      .overlay(alignment: .bottomTrailing) {
        SyncStateDot(state: account.syncState)
          .padding(1.5)
          .background(.background, in: Circle())
          .offset(x: 2, y: 2)
          .help(String(localized: "Sync: \(account.syncState.label)"))
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(account.accountName)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        if showsUserID, account.ownDisplayName != nil {
          Text(account.userID)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A button at the bottom of the sidebar that shows the active account's status and opens a
/// popover for switching, adding, and signing out of accounts.
struct AccountSwitcher: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  @State private var isPresented = false
  @State private var isHovered = false
  @State private var accountToSignOut: MatrixClient?

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        if let active = windowState.matrixClient {
          AccountLabel(account: active)
        } else {
          Text("No Account")
            .font(.body.weight(.semibold))
        }
        Spacer(minLength: 0)
        if windowState.matrixClient?.needsAttention == true {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
        }
        if appState.inactiveUnreadRoomCount > 0 {
          UnreadBadge(count: appState.inactiveUnreadRoomCount)
            .help("Unread rooms in your other accounts")
        }
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .contentShape(.rect)
      .background(
        .quaternary.opacity(isHovered || isPresented ? 1 : 0),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help("Switch account")
    .accessibilityLabel(accessibilityLabel)
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      popoverContent
    }
    // Verification requests time out, so don't leave one waiting behind a closed popover.
    .onChange(of: windowState.matrixClient?.sessionVerificationRequest?.flowId) { _, flowID in
      if flowID != nil { isPresented = true }
    }
    .confirmationDialog(
      "Sign out of \(accountToSignOut?.userID ?? "")?",
      isPresented: Binding(
        get: { accountToSignOut != nil },
        set: { if !$0 { accountToSignOut = nil } }),
      presenting: accountToSignOut
    ) { account in
      Button("Sign Out", role: .destructive) {
        Task { await appState.remove(account) }
      }
    } message: { _ in
      Text("This account will be signed out on this Mac. Your other accounts stay signed in.")
    }
  }

  private var accessibilityLabel: String {
    guard let active = windowState.matrixClient else { return String(localized: "Switch account") }
    var label = String(localized: "Switch account, current: \(active.accountMenuTitle)")
    if active.syncState != .running {
      label = String(localized: "\(label), sync: \(active.syncState.label)")
    }
    if active.needsAttention {
      label = String(localized: "\(label), needs attention")
    }
    let unread = appState.inactiveUnreadRoomCount
    return unread > 0
      ? String(localized: "\(label), \(unread) unread in other accounts") : label
  }

  private var popoverContent: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let active = windowState.matrixClient, active.hasStatus {
        AccountStatusSection(account: active) { isPresented = false }
        Divider()
          .padding(.vertical, 4)
      }

      ForEach(appState.accounts, id: \.storeID) { account in
        AccountRow(account: account, isActive: appState.activeAccountID == account.storeID) {
          appState.activate(account)
          isPresented = false
        }
      }

      Divider()
        .padding(.vertical, 4)

      PopoverActionRow(title: String(localized: "Add Account…"), systemImage: "plus") {
        isPresented = false
        windowState.loginSheet = .addAccount
      }

      if let active = windowState.matrixClient {
        PopoverActionRow(
          title: String(localized: "Sign Out of \(active.accountName)…"),
          systemImage: "rectangle.portrait.and.arrow.right"
        ) {
          isPresented = false
          accountToSignOut = active
        }
      }
    }
    .padding(6)
    .frame(width: 300)
  }
}

/// A selectable account in the switcher popover.
private struct AccountRow: View {
  let account: MatrixClient
  let isActive: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "checkmark")
          .font(.callout.weight(.semibold))
          .foregroundStyle(.tint)
          .opacity(isActive ? 1 : 0)
          .frame(width: 14)

        AccountLabel(account: account)

        Spacer(minLength: 8)

        if account.authenticationFailed {
          Text("Signed Out")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
        } else if account.unreadRoomCount > 0 {
          UnreadBadge(count: account.unreadRoomCount)
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .contentShape(.rect)
      .background(
        .quaternary.opacity(isHovered ? 1 : 0),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityAddTraits(isActive ? .isSelected : [])
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    if account.authenticationFailed { return String(localized: "Signed out") }
    var values: [String] = []
    if account.syncState != .running {
      values.append(String(localized: "Sync: \(account.syncState.label)"))
    }
    if account.unreadRoomCount > 0 {
      values.append(String(localized: "\(account.unreadRoomCount) unread"))
    }
    return values.joined(separator: ", ")
  }
}

/// The number of unread rooms, in a tinted capsule.
private struct UnreadBadge: View {
  let count: Int

  var body: some View {
    Text(verbatim: "\(count)")
      .font(.caption.weight(.semibold).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(.tint, in: Capsule())
  }
}

/// An action such as "Add Account…" at the bottom of the switcher popover.
private struct PopoverActionRow: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .frame(width: 14)
          .foregroundStyle(.secondary)
        Text(title)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .contentShape(.rect)
      .background(
        .quaternary.opacity(isHovered ? 1 : 0),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

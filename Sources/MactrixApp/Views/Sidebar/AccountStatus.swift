import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

extension SyncServiceState {
  var label: String {
    switch self {
    case .idle:
      String(localized: "idle")
    case .running:
      String(localized: "online")
    case .terminated:
      String(localized: "terminated")
    case .error:
      String(localized: "error")
    case .offline:
      String(localized: "offline")
    }
  }

  var color: Color {
    switch self {
    case .running: .green
    case .idle: .gray
    case .offline: .orange
    case .terminated, .error: .red
    }
  }

  var canRestart: Bool {
    [.error, .offline, .terminated].contains(self)
  }
}

extension MatrixClient {
  /// Whether this account needs the user to act, which the account switcher flags.
  var needsAttention: Bool {
    authenticationFailed
  }

  /// Whether the account switcher popover has anything to say about this account's status.
  var hasStatus: Bool {
    needsAttention || syncState != .running
  }
}

/// A small dot showing an account's sync state.
struct SyncStateDot: View {
  let state: SyncServiceState
  var size: CGFloat = 8

  var body: some View {
    Circle()
      .fill(state.color)
      .frame(width: size, height: size)
  }
}

/// The active account's status at the top of the account switcher popover: its sync state, and
/// anything that needs the user's attention.
struct AccountStatusSection: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  let account: MatrixClient
  /// Closes the popover, before presenting a sheet.
  let dismiss: () -> Void

  @State private var restarting = false
  @State private var removing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if account.authenticationFailed {
        signedOut
      } else if account.syncState != .running {
        syncStatus
      }
    }
  }

  /// Shown when the server has ended the account's session.
  private var signedOut: some View {
    AccountStatusItem(systemImage: "person.crop.circle.badge.exclamationmark", tint: .orange) {
      Text("You were signed out.")
    } message: {
      Text("This session was ended by the server or another device.")
    } actions: {
      Button("Sign In Again…") {
        dismiss()
        windowState.loginSheet = .signInAgain(userID: account.userID)
      }
      Button("Remove Account") {
        Task {
          removing = true
          defer { removing = false }
          await appState.remove(account)
        }
      }
      .disabled(removing)
    }
  }

  private var syncStatus: some View {
    AccountStatusItem(systemImage: "arrow.triangle.2.circlepath", tint: account.syncState.color) {
      Text("Sync: \(account.syncState.label)")
    } actions: {
      if account.syncState.canRestart {
        Button("Restart sync") {
          Task {
            restarting = true
            defer { restarting = false }

            do {
              try await account.startSync()
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

/// One status message in the account switcher popover, with optional actions below it.
struct AccountStatusItem<Title: View, Message: View, Actions: View>: View {
  let systemImage: String
  let tint: Color
  @ViewBuilder let title: Title
  @ViewBuilder let message: Message
  @ViewBuilder let actions: Actions

  init(
    systemImage: String, tint: Color,
    @ViewBuilder title: () -> Title,
    @ViewBuilder message: () -> Message = { EmptyView() },
    @ViewBuilder actions: () -> Actions = { EmptyView() }
  ) {
    self.systemImage = systemImage
    self.tint = tint
    self.title = title()
    self.message = message()
    self.actions = actions()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          title
            .font(.body.weight(.semibold))
          message
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)

        if Actions.self != EmptyView.self {
          HStack(spacing: 6) {
            actions
          }
          .controlSize(.small)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
  }
}

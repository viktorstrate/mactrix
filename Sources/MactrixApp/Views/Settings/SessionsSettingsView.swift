import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct SessionsSettingsView: View {
  @Environment(AppState.self) var appState
  @Environment(\.colorScheme) var colorScheme

  func sessionBadge(systemIcon: String, color: Color) -> some View {
    Image(systemName: systemIcon)
      .font(.system(size: 20))
      .padding(12)
      .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.2)))
      .foregroundStyle(color.mix(with: colorScheme == .light ? .black : .white, by: 0.2))
  }

  func sessionVerificationState(
    badge: some View, title: LocalizedStringKey, subtitle: LocalizedStringKey
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      badge
      VStack(alignment: .leading, spacing: 2) {
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
        title: "Verification status unknown",
        subtitle: "This device's verification status is not yet known."
      )
    case .verified:
      sessionVerificationState(
        badge: sessionBadge(systemIcon: "checkmark.shield.fill", color: .green),
        title: "This device is verified",
        subtitle: "Your account recognizes this device as trusted."
      )
    case .unverified:
      sessionVerificationState(
        badge: sessionBadge(systemIcon: "exclamationmark.shield.fill", color: .orange),
        title: "This device isn't verified",
        subtitle: "Verify this device to confirm it belongs to you."
      )
    }
  }

  @ViewBuilder
  func recoveryView(matrixClient: MatrixClient) -> some View {
    LabeledContent("Recovery on this device") {
      switch matrixClient.recoveryState {
      case nil, .unknown:
        Text("Status unknown")
      case .disabled:
        Text("Not Enabled")
      case .incomplete:
        Label("Incomplete", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      case .enabled:
        Text("Enabled")
      }
    }
    if matrixClient.recoveryState == .incomplete {
      Text(
        "Recovery is set up for your account, but this device still needs identity keys or backup setup."
      )
      .foregroundStyle(.secondary)
    }
  }

  func backupStatus(_ state: BackupState?) -> LocalizedStringKey {
    switch state {
    case nil: "Status unknown"
    case .unknown: "Not active"
    case .creating: "Creating backup…"
    case .enabling: "Enabling backup…"
    case .resuming: "Resuming backup…"
    case .enabled: "Enabled"
    case .downloading: "Downloading message keys…"
    case .disabling: "Deleting backup…"
    }
  }

  @ViewBuilder
  func serverBackupView(matrixClient: MatrixClient) -> some View {
    switch matrixClient.serverBackupState {
    case .unknown:
      Text("Status unknown")
    case .loading:
      HStack {
        ProgressView().controlSize(.small)
        Text("Checking for a backup…")
      }
    case .available(let exists):
      if exists {
        Text("Backup found")
      } else {
        Text("No backup found")
      }
    case .failed:
      HStack {
        Text("Couldn't check for a backup")
        Button("Retry") {
          Task {
            await matrixClient.refreshServerBackupState()
          }
        }
      }
    }
  }

  var body: some View {
    if let matrixClient = appState.matrixClient {
      Form {
        Section("Device Verification") {
          sessionVerificationView(matrixClient: matrixClient)
        }

        Section {
          recoveryView(matrixClient: matrixClient)
        } header: {
          Text("Message Recovery")
        }

        Section {
          LabeledContent("Backup from this device") {
            Text(backupStatus(matrixClient.backupState))
          }
          LabeledContent("Server backup") {
            serverBackupView(matrixClient: matrixClient)
          }
        } header: {
          Text("Message Key Backup")
        } footer: {
          Text(
            "Backup of the encryption keys needed to read your messages. "
          )
        }
      }
      .formStyle(.grouped)
      .task(id: matrixClient.storeID) {
        await matrixClient.refreshServerBackupState()
      }
    } else {
      ContentUnavailableView("Not signed in", systemImage: "person")
    }
  }
}

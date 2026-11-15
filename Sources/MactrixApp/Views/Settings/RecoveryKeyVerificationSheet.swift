import MatrixIntegration
import SwiftUI

struct RecoveryKeyVerificationSheet: View {
  let matrixClient: MatrixClient

  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var verificationTask: Task<Void, Never>?
  @FocusState private var keyFieldFocused: Bool
  @State private var recoveryKey = ""
  @State private var state: State = .idle

  enum State {
    case idle
    case verifying
    case recovered
    case failed(Error)

    var isVerifying: Bool {
      if case .verifying = self {
        return true
      } else {
        return false
      }
    }
  }

  var canVerify: Bool {
    switch state {
    case .idle, .failed(_):
      return !recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    default:
      return false
    }
  }

  func verify(using recover: @MainActor (String) async throws -> Void) async {
    guard canVerify else { return }
    state = .verifying

    do {
      try Task.checkCancellation()
      try await recover(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines))
      try Task.checkCancellation()
      recoveryKey = ""
      state = .recovered
    } catch {
      state = Task.isCancelled || error is CancellationError ? .idle : .failed(error)
    }
  }

  @ViewBuilder
  var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Verify with Recovery Key")
        .font(.title2)

      if case .recovered = state {
        if matrixClient.verificationState == .verified {
          Label("This device is verified", systemImage: "checkmark.shield.fill")
            .foregroundStyle(.green)
        } else {
          Label("Recovery key accepted", systemImage: "checkmark.shield")
          Text(
            "Your encryption secrets were restored. This device's verification status is still updating."
          )
          .foregroundStyle(.secondary)
        }
        Text("Access to older messages depends on which message keys are available.")
          .foregroundStyle(.secondary)
      } else {
        Text(
          "Enter your account's recovery key to restore encryption secrets and verify this device."
        )
        .foregroundStyle(.secondary)

        SecureField("Recovery key", text: $recoveryKey)
          .textFieldStyle(.roundedBorder)
          .focused($keyFieldFocused)
          .disabled(state.isVerifying)
          .onSubmit { verify() }

        if state.isVerifying {
          HStack {
            ProgressView().controlSize(.small)
            Text("Restoring encryption secrets…")
          }
        }

        if case .failed(let error) = state {
          Text(
            "Couldn't verify recovery key: \(error.localizedDescription)"
          )
          .foregroundStyle(.red)
        }
      }

      HStack {
        Spacer()
        if case .recovered = state {
          Button("Done") { dismiss() }
            .keyboardShortcut(.defaultAction)
        } else {
          Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)
          Button("Verify") { verify() }
            .keyboardShortcut(.defaultAction)
            .disabled(!canVerify || matrixClient.isRecoveringWithRecoveryKey)
        }
      }
    }
    .padding(24)
    .frame(width: 440)
    .interactiveDismissDisabled(state.isVerifying)
    .onAppear { keyFieldFocused = true }
    .onChange(of: appState.matrixClient.map { ObjectIdentifier($0) }) {
      dismiss()
    }
    .onDisappear { verificationTask?.cancel() }
  }

  var body: some View {
    if #available(macOS 15.4, *) {
      content.presentationPreventsAppTermination(false)
    } else {
      content
    }
  }

  private func verify() {
    guard appState.matrixClient === matrixClient,
      verificationTask == nil, canVerify, !matrixClient.isRecoveringWithRecoveryKey
    else { return }

    verificationTask = Task {
      await verify { recoveryKey in
        try await matrixClient.verifyWithRecoveryKey(recoveryKey)
      }
      if !Task.isCancelled {
        verificationTask = nil
      }
    }
  }
}

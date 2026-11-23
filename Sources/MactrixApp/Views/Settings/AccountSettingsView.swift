import MatrixRustSDK
import OSLog
import SwiftUI

struct ChangableField: View {
  let name: LocalizedStringKey
  let value: String
  let onSave: (_ newValue: String) async -> Void

  @State private var isEditing: Bool = false
  @State private var editValue: String = ""
  @State private var saving: Bool = false

  private func save() async {
    saving = true
    await onSave(editValue)
    isEditing = false
    saving = false
  }

  var body: some View {
    if isEditing {
      HStack {
        TextField(name, text: $editValue)
          .onSubmit { Task { await save() } }
          .disabled(saving)
        Button("Save") { Task { await save() } }
        Button("Cancel") { isEditing = false }
      }
    } else {
      LabeledContent(name) {
        Text(value)
          .textSelection(.enabled)
        Button("Edit") {
          editValue = value
          isEditing = true
        }
        .padding(.leading, 10)
      }
    }
  }
}

struct AccountSettingsView: View {
  @Environment(AppState.self) var appState

  @State private var logoutError: String? = nil
  @State private var displayName: String? = nil

  var body: some View {
    if let matrixClient = appState.matrixClient {
      Form {
        Section {
          AccountLabel(account: matrixClient)
        } header: {
          Text("Active Account")
        } footer: {
          if appState.accounts.count > 1 {
            Text("Switch accounts from the sidebar or the Account menu.")
          }
        }

        ChangableField(
          name: "Display name", value: displayName ?? String(localized: "Loading…"),
          onSave: { newDisplayName in
            do {
              try await matrixClient.client.setDisplayName(name: newDisplayName)
              displayName = newDisplayName
              await matrixClient.refreshOwnProfile()
            } catch {
              Logger.viewCycle.error("Failed to update display name: \(error)")
            }
          }
        )
        .task(id: matrixClient.storeID) {
          displayName = nil
          do {
            displayName = try await matrixClient.client.displayName()
          } catch {
            Logger.viewCycle.error("Failed to load display name: \(error)")
          }
        }

        LabeledContent("User") {
          Text((try? matrixClient.client.userId()) ?? String(localized: "Error"))
            .textSelection(.enabled)
        }

        LabeledContent("Device") {
          Text((try? matrixClient.client.deviceId()) ?? String(localized: "Error"))
            .textSelection(.enabled)
        }

        HStack {
          Button(appState.accounts.count > 1 ? "Sign Out of This Account" : "Sign out", role: .destructive) {
            Task {
              do {
                try await appState.reset()
              } catch {
                logoutError = error.localizedDescription
              }
            }
          }
          if let logoutError = logoutError {
            Text(logoutError)
              .textSelection(.enabled)
              .foregroundStyle(Color.red)
          }
        }

        Button("Clear cache") {
          Task {
            do {
              try await appState.matrixClient?.clearCache()
            } catch {
              Logger.viewCycle.error("Failed to clear cache: \(error)")
            }
          }
        }
      }
    } else {
      ContentUnavailableView("User not logged in", systemImage: "person")
    }
  }
}

#Preview {
  AccountSettingsView()
}

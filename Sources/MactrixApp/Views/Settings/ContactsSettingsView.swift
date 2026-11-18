import ContactLinking
import SwiftUI

struct ContactsSettingsView: View {
  @Bindable private var contacts = ContactDirectory.shared

  var body: some View {
    Form {
      Section {
        Toggle("Show linked contacts", isOn: $contacts.isEnabled)
      } footer: {
        Text(
          "Link a Matrix user to one of your contacts from their profile. The link is stored as a “Matrix” social profile on the contact. Contact names and photos are only shown on this Mac and are never sent to other Matrix users."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Section {
        Toggle("Use contact names", isOn: $contacts.useContactNames)
        Toggle("Prefer nicknames", isOn: $contacts.preferNicknames)
          .disabled(!contacts.useContactNames)
        Toggle("Use contact photos", isOn: $contacts.useContactPhotos)
      }
      .disabled(!contacts.isEnabled)

      Section("Access") {
        LabeledContent("Contacts access") {
          accessStatus
        }
        LabeledContent("Linked contacts") {
          Text(verbatim: "\(Set(contacts.linksByUserID.values.map(\.identifier)).count)")
        }
      }
      .disabled(!contacts.isEnabled)
    }
    .formStyle(.grouped)
    .onAppear {
      contacts.refreshAuthorizationStatus()
    }
  }

  @ViewBuilder
  private var accessStatus: some View {
    switch contacts.authorizationStatus {
    case .authorized:
      Label("Granted", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .notDetermined:
      Button("Grant Access…") {
        Task { await contacts.requestAccessAndReload() }
      }
    default:
      HStack {
        Label("Denied", systemImage: "xmark.circle.fill")
          .foregroundStyle(.red)
        Button("Open Privacy Settings") {
          contacts.openPrivacySettings()
        }
      }
    }
  }
}

#Preview {
  ContactsSettingsView()
    .frame(width: 620, height: 500)
}

import ContactLinking
import OSLog
import SwiftUI

/// Lets the user pick a system contact to link to a Matrix user.
struct ContactPickerSheet: View {
  let userID: String
  let matrixName: String?

  @Environment(\.dismiss) private var dismiss

  @State private var contacts: [ContactSummary] = []
  @State private var query = ""
  @State private var selection: ContactSummary.ID?
  @State private var isLoading = true
  @State private var isLinking = false
  @State private var errorMessage: String?

  private var filteredContacts: [ContactSummary] {
    contacts.filter { $0.matches(query) }
  }

  private var title: String {
    if let matrixName, !matrixName.isEmpty {
      String(localized: "Link “\(matrixName)” to a Contact")
    } else {
      String(localized: "Link \(userID) to a Contact")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)

      TextField("Search Contacts", text: $query)
        .textFieldStyle(.roundedBorder)

      List(filteredContacts, selection: $selection) { contact in
        ContactPickerRow(contact: contact, userID: userID)
          .tag(contact.id)
      }
      .contextMenu(forSelectionType: ContactSummary.ID.self) { _ in
      } primaryAction: { identifiers in
        if let identifier = identifiers.first {
          link(contactIdentifier: identifier)
        }
      }
      .overlay {
        if isLoading {
          ProgressView()
        } else if filteredContacts.isEmpty {
          if query.isEmpty {
            ContentUnavailableView("No Contacts", systemImage: "person.crop.circle")
          } else {
            ContentUnavailableView.search(text: query)
          }
        }
      }

      HStack {
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .lineLimit(2)
        }
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Link") {
          if let selection {
            link(contactIdentifier: selection)
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selection == nil || isLinking)
      }
    }
    .padding()
    .frame(width: 420, height: 480)
    .task {
      do {
        contacts = try await ContactDirectory.shared.allContacts()
        selection = ContactDirectory.shared.linkedContact(for: userID)?.identifier
      } catch {
        Logger.viewCycle.error("Failed to load contacts: \(error)")
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func link(contactIdentifier: String) {
    guard !isLinking else { return }
    isLinking = true
    Task {
      defer { isLinking = false }
      do {
        try await ContactDirectory.shared.link(
          userID: userID, toContactIdentifier: contactIdentifier)
        dismiss()
      } catch {
        Logger.viewCycle.error("Failed to link contact: \(error)")
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct ContactPickerRow: View {
  let contact: ContactSummary
  let userID: String

  private var subtitle: String? {
    let normalizedUserID = MatrixSocialProfile.normalize(userID) ?? userID
    if contact.linkedUserIDs.contains(normalizedUserID) {
      return String(localized: "Currently linked")
    }
    if !contact.linkedUserIDs.isEmpty {
      return String(localized: "Linked to \(contact.linkedUserIDs.joined(separator: ", "))")
    }
    return nil
  }

  var body: some View {
    HStack {
      ContactThumbnail(data: contact.thumbnailData)
        .frame(width: 28, height: 28)
      VStack(alignment: .leading) {
        Text(contact.name)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .padding(.vertical, 2)
  }
}

private struct ContactThumbnail: View {
  let data: Data?

  var body: some View {
    if let data, let image = NSImage(data: data) {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .clipShape(Circle())
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .scaledToFit()
        .foregroundStyle(.secondary)
    }
  }
}

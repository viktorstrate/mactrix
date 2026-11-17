import ContactLinking
import MatrixProtocols
import OSLog
import SwiftUI

@MainActor
public protocol UserProfileActions {
  func sendMessage() async
  func shareProfile()
  func ignoreUser() async
  func unignoreUser() async
}

public protocol UserProfileTimelineActions {
  func jumpToReadReceipt()
  func mentionUser()
}

public struct UserProfileView<Profile: UserProfile>: View {
  let profile: Profile
  let isUserIgnored: Bool
  let actions: UserProfileActions?
  let timelineActions: UserProfileTimelineActions?
  let imageLoader: ImageLoader?

  @State private var ignoreUserLoading: Bool = false
  @State private var sendMessageLoading: Bool = false
  @State private var isPickingContact: Bool = false
  @State private var contactActionLoading: Bool = false
  @State private var contactError: String?

  private var contacts: ContactDirectory { .shared }

  private var linkedContact: LinkedContact? {
    contacts.linkedContact(for: profile.userId)
  }

  public init(
    profile: Profile, isUserIgnored: Bool, actions: UserProfileActions?,
    timelineActions: UserProfileTimelineActions?, imageLoader: ImageLoader?
  ) {
    self.profile = profile
    self.isUserIgnored = isUserIgnored
    self.actions = actions
    self.timelineActions = timelineActions
    self.imageLoader = imageLoader
  }

  @ViewBuilder
  var profileHeader: some View {
    VStack(alignment: .center) {
      AvatarImage(userProfile: profile, imageLoader: imageLoader)
        .allowsHitTesting(false)
        .frame(width: 72, height: 72)
        .padding(.bottom, 6)

      Username(userProfile: profile)
      if contacts.contactName(for: profile.userId) != nil,
        let matrixName = profile.displayName, !matrixName.isEmpty
      {
        Text("Matrix name: \(matrixName)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      Text(profile.userId)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .contentShape(Rectangle())
    .onDrag {
      do {
        return try UserDragPayload(
          userId: profile.userId,
          username: profile.displayName ?? profile.userId,
          avatarUrl: profile.avatarUrl
        ).makeItemProvider()
      } catch {
        Logger.viewCycle.error("Failed to prepare user drag: \(error)")
        return NSItemProvider()
      }
    } preview: {
      UserProfileRow(profile: profile, imageLoader: imageLoader)
    }
    .frame(maxWidth: .infinity)
    .listRowSeparator(.hidden)
    .padding(.top)
  }

  @ViewBuilder
  var contactSection: some View {
    Section("Contact") {
      if !contacts.isEnabled {
        Text("Show names and photos from your contacts for linked Matrix users.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Button {
          contacts.isEnabled = true
        } label: {
          Label("Use Contacts", systemImage: "person.crop.circle.badge.checkmark")
        }
        .buttonStyle(.link)
      } else if contacts.authorizationStatus == .notDetermined {
        Button {
          Task { await contacts.requestAccessAndReload() }
        } label: {
          Label("Grant Access to Contacts…", systemImage: "person.crop.circle.badge.checkmark")
        }
        .buttonStyle(.link)
      } else if !contacts.isAuthorized {
        Text("Mactrix doesn't have access to your contacts.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Button {
          contacts.openPrivacySettings()
        } label: {
          Label("Open Privacy Settings", systemImage: "gear")
        }
        .buttonStyle(.link)
      } else if linkedContact != nil {
        Button {
          isPickingContact = true
        } label: {
          Label("Change Linked Contact…", systemImage: "person.crop.circle")
        }
        .buttonStyle(.link)

        Button {
          contacts.openInContacts(userID: profile.userId)
        } label: {
          Label("Open in Contacts", systemImage: "person.text.rectangle")
        }
        .buttonStyle(.link)

        Button {
          Task {
            contactActionLoading = true
            defer { contactActionLoading = false }
            do {
              try await contacts.unlink(userID: profile.userId)
              contactError = nil
            } catch {
              Logger.viewCycle.error("Failed to unlink contact: \(error)")
              contactError = error.localizedDescription
            }
          }
        } label: {
          Label("Unlink Contact", systemImage: "person.crop.circle.badge.xmark")
        }
        .buttonStyle(.link)
        .disabled(contactActionLoading)
      } else {
        Button {
          isPickingContact = true
        } label: {
          Label("Link to Contact…", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(.link)
      }

      if let contactError {
        Text(contactError)
          .font(.callout)
          .foregroundStyle(.red)
      }
    }
    .onAppear {
      contacts.refreshAuthorizationStatus()
    }
    .sheet(isPresented: $isPickingContact) {
      ContactPickerSheet(userID: profile.userId, matrixName: profile.displayName)
    }
  }

  public var body: some View {
    List {
      profileHeader

      Section("Timeline") {
        Button(action: { timelineActions?.jumpToReadReceipt() }) {
          Label("Jump to read receipt", systemImage: "checkmark.circle")
        }
        .buttonStyle(.link)

        Button(action: { timelineActions?.mentionUser() }) {
          Label("Mention", systemImage: "at")
        }
        .buttonStyle(.link)
      }
      .disabled(timelineActions == nil)

      contactSection
        .disabled(actions == nil)

      Section("Actions") {
        Button {
          Task {
            sendMessageLoading = true
            defer { sendMessageLoading = false }

            await actions?.sendMessage()
          }
        } label: {
          Label("Send message", systemImage: "envelope")
        }
        .buttonStyle(.link)
        .disabled(sendMessageLoading)

        Button(action: { actions?.shareProfile() }) {
          Label("Share profile", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.link)

        if !isUserIgnored {
          Button {
            Task {
              ignoreUserLoading = true
              defer { ignoreUserLoading = false }
              await actions?.ignoreUser()
            }
          } label: {
            Label("Ignore user", systemImage: "person.slash")
          }
          .buttonStyle(.link)
          .foregroundStyle(.red)
          .disabled(ignoreUserLoading)
        } else {
          Button {
            Task {
              ignoreUserLoading = true
              defer { ignoreUserLoading = false }
              await actions?.unignoreUser()
            }
          } label: {
            Label("Unignore user", systemImage: "person.slash.fill")
          }
          .buttonStyle(.link)
          .foregroundStyle(.red)
          .disabled(ignoreUserLoading)
        }
      }
      .disabled(actions == nil)
    }
  }
}

struct MockUserProfileActions: UserProfileActions {
  func sendMessage() {}
  func shareProfile() {}
  func ignoreUser() {}
  func unignoreUser() {}
}

#Preview {
  UserProfileView(
    profile: MockUserProfile(), isUserIgnored: false, actions: MockUserProfileActions(),
    timelineActions: nil, imageLoader: nil
  )
  .frame(width: 250, height: 500)
}

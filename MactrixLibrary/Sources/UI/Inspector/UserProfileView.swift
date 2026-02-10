import Models
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

    public init(profile: Profile, isUserIgnored: Bool, actions: UserProfileActions?, timelineActions: UserProfileTimelineActions?, imageLoader: ImageLoader?) {
        self.profile = profile
        self.isUserIgnored = isUserIgnored
        self.actions = actions
        self.timelineActions = timelineActions
        self.imageLoader = imageLoader
    }

    @ViewBuilder
    var profileHeader: some View {
        VStack(alignment: .center) {
            AvatarImage(avatarUrl: profile.avatarUrl, imageLoader: imageLoader, id: profile.userId, name: profile.displayName)
                .frame(width: 72, height: 72)
                .clipShape(.circle)
                .padding(.bottom, 6)

            Text(profile.displayName ?? "No display name")
                .textSelection(.enabled)
            Text(profile.userId)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .padding(.top)
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
    UserProfileView(profile: MockUserProfile(), isUserIgnored: false, actions: MockUserProfileActions(), timelineActions: nil, imageLoader: nil)
        .frame(width: 250, height: 500)
}

import Models
import SwiftUI

public struct UserProfileRow<Profile: UserProfile>: View {
    let profile: Profile
    let imageLoader: ImageLoader?

    @State private var image: Image? = nil

    public init(profile: Profile, imageLoader: ImageLoader?) {
        self.profile = profile
        self.imageLoader = imageLoader
    }

    public var body: some View {
        Label {
            Username(id: profile.userId, name: profile.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(profile.displayName ?? profile.userId)
        } icon: {
            AvatarImage(avatarUrl: profile.avatarUrl, imageLoader: imageLoader, id: profile.userId, name: profile.displayName)
                .clipShape(Circle())
        }
    }
}

public struct UserProfileRowLarge<Profile: UserProfile>: View {
    let profile: Profile
    let imageLoader: ImageLoader?

    public init(profile: Profile, imageLoader: ImageLoader?) {
        self.profile = profile
        self.imageLoader = imageLoader
    }

    public var body: some View {
        HStack {
            AvatarImage(avatarUrl: profile.avatarUrl, imageLoader: imageLoader, id: profile.userId, name: profile.displayName)
                .frame(width: 32, height: 32)
                .clipShape(.circle)
            VStack(alignment: .leading) {
                Username(id: profile.userId, name: profile.displayName ?? "No display name")
                    .textSelection(.enabled)
                Text(profile.userId)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }
}

#Preview {
    List {
        UserProfileRow(profile: MockUserProfile(), imageLoader: nil)
        UserProfileRow(profile: MockUserProfile(), imageLoader: nil)
        UserProfileRow(profile: MockUserProfile(), imageLoader: nil)
        
        UserProfileRowLarge(profile: MockUserProfile(), imageLoader: nil)
        UserProfileRowLarge(profile: MockUserProfile(), imageLoader: nil)
        UserProfileRowLarge(profile: MockUserProfile(), imageLoader: nil)
    }
    .frame(width: 250)
}

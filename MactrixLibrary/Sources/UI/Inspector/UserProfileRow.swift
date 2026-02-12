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
            Username(userProfile: profile)
        } icon: {
            AvatarImage(userProfile: profile, imageLoader: imageLoader)
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
            AvatarImage(userProfile: profile, imageLoader: imageLoader)
                .frame(width: 32, height: 32)
                .clipShape(.circle)
            VStack(alignment: .leading) {
                Username(userProfile: profile)
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

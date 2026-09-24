import Models
import OSLog
import SwiftUI

@MainActor
public protocol ImageLoader {
    func loadImage(matrixUrl: String, size: CGSize?) async throws -> NSImage?
    func cachedImage(matrixUrl: String) -> NSImage?
}

public struct AvatarImage<Preview: View>: View {
    let avatarUrl: String?
    let placeholder: () -> Preview
    let imageLoader: ImageLoader?

    public init(
        avatarUrl: String?,
        imageLoader: ImageLoader?,
        placeholder: @escaping () -> Preview = {
            Rectangle().foregroundStyle(Color.gray)
        }
    ) {
        self.avatarUrl = avatarUrl
        self.imageLoader = imageLoader
        self.placeholder = placeholder
        if let avatarUrl, let cached = imageLoader?.cachedImage(matrixUrl: avatarUrl) {
            self._avatar = State(initialValue: Image(nsImage: cached))
        }
    }

    public init<Profile: UserProfile>(
        userProfile: Profile,
        imageLoader: ImageLoader?
    ) where Preview == UserAvatarPlaceholder<Profile> {
        self.init(avatarUrl: userProfile.avatarUrl, imageLoader: imageLoader) {
            UserAvatarPlaceholder(userProfile: userProfile)
        }
    }

    @State private var avatar: Image? = nil

    @ViewBuilder
    var imageOrPlaceholder: some View {
        if let avatar = avatar {
            avatar.resizable()
        } else {
            placeholder()
        }
    }

    public var body: some View {
        imageOrPlaceholder
            .scaledToFill()
            .transaction { $0.animation = nil }
            .task(id: avatarUrl, priority: .utility) {
                guard let avatarUrl else {
                    avatar = nil
                    return
                }

                // Check cache first (handles cell reuse with stale @State)
                if let cached = imageLoader?.cachedImage(matrixUrl: avatarUrl) {
                    avatar = Image(nsImage: cached)
                    return
                }

                avatar = nil

                do {
                    if let image = try await imageLoader?.loadImage(matrixUrl: avatarUrl, size: nil) {
                        avatar = Image(nsImage: image)
                    } else {
                        avatar = nil
                    }
                } catch {
                    Logger.viewCycle.error("failed to load avatar (\(avatarUrl): \(error)")
                }
            }
    }
}

public struct UserAvatarPlaceholder<Profile: UserProfile>: View {
    let userProfile: Profile

    public var body: some View {
        GeometryReader { g in
            ZStack {
                Color(userID: userProfile.id)

                if
                    let initial = (userProfile.displayName ?? userProfile.id).uppercased().filter({ $0 != Character("@") }).first.map({ String($0) })
                {
                    Text(initial)
                        .font(.system(size: g.size.width * 0.7))
                        .fontWeight(.bold)
                        .foregroundStyle(.background)
                }
            }
        }
    }
}

#Preview {
    AvatarImage(userProfile: MockUserProfile(), imageLoader: nil)
        .frame(width: 200, height: 200)
        .background(Circle().fill(.blue))
        .clipShape(Circle())

    AvatarImage(userProfile: MockUserProfile(), imageLoader: nil)
        .frame(width: 100, height: 100)
        .background(Circle().fill(.blue))
        .clipShape(Circle())

    AvatarImage(userProfile: MockUserProfile(), imageLoader: nil)
        .frame(width: 25, height: 25)
        .background(Circle().fill(.blue))
        .clipShape(Circle())
}

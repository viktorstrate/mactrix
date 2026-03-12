import Models
import OSLog
import SwiftUI

@MainActor
public protocol ImageLoader {
    func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image?
    func cachedImage(matrixUrl: String) -> Image?
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
            self._avatar = State(initialValue: cached)
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
                    avatar = cached
                    return
                }

                avatar = nil

                do {
                    avatar = try await imageLoader?.loadImage(matrixUrl: avatarUrl, size: nil)
                } catch {
                    Logger.viewCycle.error("failed to load avatar (\(avatarUrl): \(error)")
                }
            }
    }
}

public struct UserAvatarPlaceholder<Profile: UserProfile>: View {
    let userProfile: Profile

    public var body: some View {
        ZStack {
            Color(userID: userProfile.id)

            if
                let initial = (userProfile.displayName ?? userProfile.id).uppercased().filter({ $0 != Character("@") }).first.map({ String($0) })
            {
                Text(initial)
                    .font(.system(size: 100))
                    .fontWeight(.bold)
                    .foregroundStyle(.background)
                    .minimumScaleFactor(0.01)
            }
        }
    }
}

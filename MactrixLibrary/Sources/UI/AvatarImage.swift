import OSLog
import SwiftUI

@MainActor
public protocol ImageLoader {
    func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image?
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
    }
    
    public init(
        avatarUrl: String?,
        imageLoader: ImageLoader?,
        id: String,
        name: String?
    ) where Preview == UserAvatarPlaceholder {
        self.init(avatarUrl: avatarUrl, imageLoader: imageLoader) {
            UserAvatarPlaceholder(id: id, name: name)
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
        GeometryReader { proxy in
            imageOrPlaceholder
                .aspectRatio(1.0, contentMode: .fit)
                .task(id: avatarUrl) {
                    guard let avatarUrl = avatarUrl else {
                        avatar = nil
                        return
                    }

                    do {
                        avatar = try await imageLoader?.loadImage(matrixUrl: avatarUrl, size: proxy.size)
                    } catch {
                        Logger.viewCycle.error("failed to load avatar (\(avatarUrl): \(error)")
                    }
                }
        }
    }
}

public struct UserAvatarPlaceholder: View {
    let id: String
    let name: String?
    
    public var body: some View {
        GeometryReader { g in
            ZStack {
                Color(userID: id)
                
                if
                    let initial = (name ?? id).uppercased().filter({ $0 != Character("@") }).first.map({ String($0) })
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

import MatrixProtocols
import OSLog
import SwiftUI

@MainActor
public protocol ImageLoader {
  func loadImage(matrixUrl: String, size: CGSize?) async throws -> NSImage?
  func cachedImage(matrixUrl: String) -> NSImage?
}

public struct UserAvatarImage: NSViewRepresentable {
  private let userID: String
  private let displayName: String?
  private let avatarUrl: String?
  private let imageLoader: ImageLoader?

  public init<Profile: UserProfile>(userProfile: Profile, imageLoader: ImageLoader?) {
    userID = userProfile.id
    displayName = userProfile.displayName
    avatarUrl = userProfile.avatarUrl
    self.imageLoader = imageLoader
  }

  public func makeNSView(context: Context) -> UserAvatarView {
    let view = UserAvatarView()
    configure(view)
    return view
  }

  public func updateNSView(_ view: UserAvatarView, context: Context) {
    configure(view)
  }

  public func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: UserAvatarView, context: Context
  ) -> CGSize? {
    let width = proposal.width ?? nsView.intrinsicContentSize.width
    let height = proposal.height ?? nsView.intrinsicContentSize.height
    let size = min(width, height)
    return CGSize(width: size, height: size)
  }

  public static func dismantleNSView(_ view: UserAvatarView, coordinator: ()) {
    view.cancelLoad()
  }

  private func configure(_ view: UserAvatarView) {
    view.configure(
      userID: userID, displayName: displayName, avatarUrl: avatarUrl, imageLoader: imageLoader
    )
  }
}

public struct RoomAvatarImage: View {
  private let avatarUrl: String?
  private let imageLoader: ImageLoader?

  public init(avatarUrl: String?, imageLoader: ImageLoader?) {
    self.avatarUrl = avatarUrl
    self.imageLoader = imageLoader
  }

  public var body: some View {
    RemoteAvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
      Rectangle().foregroundStyle(Color.gray)
    }
    .clipShape(.circle)
  }
}

public struct RoomRowAvatarImage: View {
  private let avatarUrl: String?
  private let placeholderSystemImage: String
  private let imageLoader: ImageLoader?

  public init(
    avatarUrl: String?, placeholderSystemImage: String, imageLoader: ImageLoader?
  ) {
    self.avatarUrl = avatarUrl
    self.placeholderSystemImage = placeholderSystemImage
    self.imageLoader = imageLoader
  }

  public var body: some View {
    RemoteAvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
      Rectangle()
        .fill(.clear)
        .overlay {
          Image(systemName: placeholderSystemImage)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct RemoteAvatarImage<Placeholder: View>: View {
  let avatarUrl: String?
  let imageLoader: ImageLoader?
  let placeholder: () -> Placeholder

  @State private var avatar: Image?

  init(
    avatarUrl: String?, imageLoader: ImageLoader?,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.avatarUrl = avatarUrl
    self.imageLoader = imageLoader
    self.placeholder = placeholder
    if let avatarUrl, let cached = imageLoader?.cachedImage(matrixUrl: avatarUrl) {
      _avatar = State(initialValue: Image(nsImage: cached))
    } else {
      _avatar = State(initialValue: nil)
    }
  }

  @ViewBuilder
  private var imageOrPlaceholder: some View {
    if let avatar {
      avatar.resizable()
    } else {
      placeholder()
    }
  }

  var body: some View {
    imageOrPlaceholder
      .scaledToFill()
      .transaction { $0.animation = nil }
      .task(id: avatarUrl, priority: .utility) {
        guard let avatarUrl else {
          avatar = nil
          return
        }

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

#Preview {
  UserAvatarImage(userProfile: MockUserProfile(), imageLoader: nil)
    .frame(width: 100, height: 100)

  RoomAvatarImage(avatarUrl: nil, imageLoader: nil)
    .frame(width: 72, height: 72)

  RoomRowAvatarImage(
    avatarUrl: nil, placeholderSystemImage: "number", imageLoader: nil
  )
  .frame(width: 22, height: 22)
}

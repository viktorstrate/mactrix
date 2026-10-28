import MatrixProtocols
import OSLog
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
      Username(userProfile: profile, isSelectable: false)
    } icon: {
      AvatarImage(userProfile: profile, imageLoader: imageLoader)
        .allowsHitTesting(false)
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
        .allowsHitTesting(false)
      VStack(alignment: .leading) {
        Username(userProfile: profile, isSelectable: false)
        Text(profile.userId)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
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

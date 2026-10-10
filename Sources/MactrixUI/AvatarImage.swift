import MatrixProtocols
import OSLog
import SwiftUI

@MainActor
public protocol ImageLoader: AnyObject {
  func loadImage(matrixUrl: String, size: CGSize?) async throws -> NSImage?
  func cachedImage(matrixUrl: String, size: CGSize?) -> NSImage?
}

public struct AvatarImage: View {
  private let roomID: String
  private let kind: AvatarKind
  private let displayName: String?
  private let avatarUrl: String?
  private let imageLoader: ImageLoader?
  @ScaledMetric(relativeTo: .body) private var baselineOffset: CGFloat =
    NSFont.preferredFont(forTextStyle: .body).capHeight / 2

  public init(userProfile: some UserProfile, imageLoader: ImageLoader?) {
    roomID = userProfile.id
    kind = .user
    displayName = userProfile.displayName
    avatarUrl = userProfile.avatarUrl
    self.imageLoader = imageLoader
  }

  public init(roomInfo: some RoomInfo, imageLoader: ImageLoader?) {
    roomID = roomInfo.id
    kind = .room
    displayName = roomInfo.displayName
    avatarUrl = roomInfo.avatarUrl
    self.imageLoader = imageLoader
  }

  public init(
    userID: String, kind: AvatarKind, displayName: String?, avatarUrl: String?,
    imageLoader: ImageLoader?
  ) {
    self.roomID = userID
    self.kind = kind
    self.displayName = displayName
    self.avatarUrl = avatarUrl
    self.imageLoader = imageLoader
  }

  public var body: some View {
    let baselineOffset = self.baselineOffset

    return AvatarRepresentable(
      roomID: roomID, kind: kind, displayName: displayName, avatarUrl: avatarUrl,
      imageLoader: imageLoader
    )
    .alignmentGuide(.firstTextBaseline) { dimensions in
      dimensions[VerticalAlignment.center] + baselineOffset
    }
    .alignmentGuide(.lastTextBaseline) { dimensions in
      dimensions[VerticalAlignment.center] + baselineOffset
    }
  }
}

private struct AvatarRepresentable: NSViewRepresentable {
  let roomID: String
  let kind: AvatarKind
  let displayName: String?
  let avatarUrl: String?
  let imageLoader: ImageLoader?

  func makeNSView(context: Context) -> AvatarView {
    let view = AvatarView()
    configure(view)
    return view
  }

  func updateNSView(_ view: AvatarView, context: Context) {
    configure(view)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: AvatarView, context: Context
  ) -> CGSize? {
    let width = proposal.width ?? nsView.intrinsicContentSize.width
    let height = proposal.height ?? nsView.intrinsicContentSize.height
    let size = min(width, height)
    return CGSize(width: size, height: size)
  }

  static func dismantleNSView(_ view: AvatarView, coordinator: ()) {
    view.cancelLoad()
  }

  private func configure(_ view: AvatarView) {
    view.configure(
      userID: roomID, displayName: displayName, avatarUrl: avatarUrl, kind: kind,
      imageLoader: imageLoader
    )
  }
}

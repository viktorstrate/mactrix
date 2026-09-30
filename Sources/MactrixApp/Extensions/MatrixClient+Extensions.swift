import AppKit
import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog

extension MatrixClient {
  @MainActor
  struct MatrixClientRoomPreviewActions: @MainActor RoomPreviewActions {
    let roomId: String
    let matrixClient: MatrixClient
    let windowState: WindowState

    func joinRoom() async throws {
      let room = try await matrixClient.client.joinRoomById(roomId: roomId)
      let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
      windowState.selectedScreen = .joinedRoom(timeline: timeline)
    }

    func knockRoom() async throws {
      let room = try await matrixClient.client.knock(
        roomIdOrAlias: roomId, reason: nil, serverNames: ["matrix.org"])
      let timeline = LiveTimeline(room: LiveRoom(matrixRoom: room))
      windowState.selectedScreen = .joinedRoom(timeline: timeline)
    }

    func visitRoom() {
      windowState.selectedRoomId = roomId
    }
  }

  func roomPreviewActions(forRoomWithId roomId: String, windowState: WindowState)
    -> RoomPreviewActions
  {
    return MatrixClientRoomPreviewActions(
      roomId: roomId, matrixClient: self, windowState: windowState)
  }
}

extension MatrixClient: MactrixUI.ImageLoader {
  // In-memory cache of decoded NSImage objects. Purpose is rendering performance —
  // keeping decoded bitmaps ready to display prevents flicker when scrolling back to
  // previously viewed images. This is distinct from the SDK-level media download cache
  // (see clearCaches / getMediaFile(useCache:)) which avoids re-fetching from the server.
  // Costs are tracked in decoded RGBA bytes (width × height × 4), not compressed sizes,
  // since a typical JPEG can be 20-50× larger once decoded.
  static let imageCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.totalCostLimit = 256 * 1024 * 1024  // 256MB decoded pixels
    return cache
  }()

  private static let imageCacheMaxObjectCost = 64 * 1024 * 1024  // 64MB per object (~8000x2000px RGBA)

  static func setCachedImage(_ image: NSImage, forKey key: NSString) {
    let cost = Int(image.size.width * image.size.height) * 4  // decoded RGBA bytes
    guard cost <= imageCacheMaxObjectCost else { return }
    imageCache.setObject(image, forKey: key, cost: cost)
  }

  public func cachedImage(matrixUrl: String) -> NSImage? {
    return Self.imageCache.object(forKey: NSString(string: matrixUrl))
  }

  public func loadImage(matrixUrl: String, size: CGSize?) async throws -> NSImage? {
    let cacheKey =
      if let size {
        NSString(string: "\(matrixUrl)_\(Int(size.width))x\(Int(size.height))")
      } else {
        NSString(string: matrixUrl)
      }
    if let cached = Self.imageCache.object(forKey: cacheKey) {
      return cached
    }

    let mediaSource = try MediaSource.fromUrl(url: matrixUrl)

    let imageData: Data
    if let size {
      let width = UInt64(size.width)
      let height = UInt64(size.height)
      imageData = try await client.getMediaThumbnail(
        mediaSource: mediaSource, width: width, height: height)
    } else {
      imageData = try await client.getMediaContent(mediaSource: mediaSource)
    }

    do {
      let nsImage = try imageData.toOrientedImage(contentType: imageData.computeMimeType())
      Self.setCachedImage(nsImage, forKey: cacheKey)
      return nsImage
    } catch {
      Logger.matrixClient.error(
        "failed convert matrix media data to Image: \(error) \(imageData)")
      throw error
    }
  }
}

extension MatrixClient {
  @MainActor
  struct MatrixClientUserProfileActions: MactrixUI.UserProfileActions {
    let userId: String
    let matrixClient: MatrixClient
    let windowState: WindowState

    func sendMessage() async {
      do {
        if let room = try matrixClient.client.getDmRoom(userId: userId) {
          windowState.selectedRoomId = room.id
          return
        }

        let createRoomParams = MatrixRustSDK.CreateRoomParameters(
          name: nil, isEncrypted: false, isDirect: true, visibility: .private,
          preset: .privateChat, invite: [userId]
        )
        let roomId = try await matrixClient.client.createRoom(request: createRoomParams)
        windowState.selectedRoomId = roomId
      } catch {
        Logger.viewCycle.error("failed to get DM room for user \(userId): \(error)")
      }
    }

    func shareProfile() {}

    func ignoreUser() async {
      Logger.viewCycle.info("Ignore user \(userId)")
      do {
        try await matrixClient.client.ignoreUser(userId: userId)
      } catch {
        Logger.viewCycle.error("failed to ignore user: \(error)")
      }
    }

    func unignoreUser() async {
      Logger.viewCycle.info("Unignore user \(userId)")
      do {
        try await matrixClient.client.unignoreUser(userId: userId)
      } catch {
        Logger.viewCycle.error("failed to unignore user: \(error)")
      }
    }
  }

  func userProfileActions(forUserId userId: String, windowState: WindowState) -> some MactrixUI
    .UserProfileActions
  {
    return MatrixClientUserProfileActions(
      userId: userId, matrixClient: self, windowState: windowState)
  }
}

import AppKit
import MatrixIntegration

/// Caches successful and unsuccessful profile lookups and only retains attachments weakly.
@MainActor
final class MentionAvatarLoader {
  typealias AvatarURLLookup = @MainActor (String) async throws -> String?

  private static let clientLoaders = NSMapTable<MatrixClient, MentionAvatarLoader>(
    keyOptions: .weakMemory, valueOptions: .strongMemory)

  static func shared(for matrixClient: MatrixClient) -> MentionAvatarLoader {
    if let loader = clientLoaders.object(forKey: matrixClient) { return loader }
    let loader = MentionAvatarLoader { [weak matrixClient] userID in
      guard let matrixClient else { return nil }
      return try await matrixClient.client.getProfile(userId: userID).avatarUrl
    }
    clientLoaders.setObject(loader, forKey: matrixClient)
    return loader
  }

  private let lookup: AvatarURLLookup
  private var avatarURLs: [String: String] = [:]
  private var attemptedUserIDs: Set<String> = []
  private var tasks: [String: Task<Void, Never>] = [:]
  private var pendingAttachments: [String: NSHashTable<MentionAttachment>] = [:]

  init(lookup: @escaping AvatarURLLookup) {
    self.lookup = lookup
  }

  deinit {
    for task in tasks.values { task.cancel() }
  }

  func cancel() {
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
    pendingAttachments.removeAll()
    attemptedUserIDs = Set(avatarURLs.keys)
  }

  func restoreAvatars(in text: NSAttributedString) {
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      guard let mention = value as? MentionAttachment, mention.avatarUrl == nil else { return }
      let userID = mention.payload.userId
      if let url = avatarURLs[userID] {
        mention.setAvatarUrl(url)
        return
      }
      if let pending = pendingAttachments[userID] {
        pending.add(mention)
        return
      }
      guard attemptedUserIDs.insert(userID).inserted else { return }
      let pending = NSHashTable<MentionAttachment>.weakObjects()
      pending.add(mention)
      pendingAttachments[userID] = pending
      let lookup = lookup
      tasks[userID] = Task { [weak self] in
        let url = try? await lookup(userID)
        guard !Task.isCancelled, let self else { return }
        self.avatarURLs[userID] = url
        let attachments = self.pendingAttachments.removeValue(forKey: userID)
        self.tasks.removeValue(forKey: userID)
        if let url {
          for attachment in attachments?.allObjects ?? [] { attachment.setAvatarUrl(url) }
        }
      }
    }
  }
}

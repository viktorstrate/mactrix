import MatrixRustSDK
import OSLog
import Observation

@MainActor
protocol RecentReactionsClient {
  func load() async throws -> [String]
  func add(_ key: String) async throws
}

@MainActor
struct SDKRecentReactionsClient: RecentReactionsClient {
  private weak var client: (any ClientProtocol)?

  init(client: any ClientProtocol) {
    self.client = client
  }

  func load() async throws -> [String] {
    guard let client else { throw CancellationError() }
    return try await client.getRecentEmojis().map(\.emoji)
  }

  func add(_ key: String) async throws {
    guard let client else { throw CancellationError() }
    try await client.addRecentEmoji(emoji: key)
  }
}

/// Owned by a single account.
@MainActor @Observable
public final class RecentReactionsStore {
  @ObservationIgnored private let client: any RecentReactionsClient
  @ObservationIgnored private var requestGeneration: UInt64 = 0

  public private(set) var cachedKeys: [String] = []
  public private(set) var isActive = true

  init(client: any RecentReactionsClient) {
    self.client = client
  }

  public func invalidate() {
    isActive = false
  }

  public func refresh() async -> [String]? {
    guard isActive, !Task.isCancelled else { return nil }
    requestGeneration &+= 1
    let request = requestGeneration

    do {
      let keys = try await client.load()
      guard isActive, !Task.isCancelled,
        request == requestGeneration
      else { return nil }
      cachedKeys = keys
      return keys
    } catch {
      if !(error is CancellationError), !Task.isCancelled {
        Logger.matrixClient.error("Failed to load recent reactions: \(error)")
      }
      return nil
    }
  }

  public func toggleReaction(
    _ key: String, operation: @MainActor () async throws -> Bool
  ) async throws {
    let added = try await operation()
    guard added, isActive, !Task.isCancelled else { return }

    // Discard pending reads that started before this write. A successful write
    // starts a new refresh, which also supersedes reads started during the write.
    requestGeneration &+= 1
    do {
      try await client.add(key)
    } catch {
      if !(error is CancellationError), !Task.isCancelled {
        Logger.matrixClient.error("Failed to save recent reaction: \(error)")
      }
      return
    }
    _ = await refresh()
  }
}

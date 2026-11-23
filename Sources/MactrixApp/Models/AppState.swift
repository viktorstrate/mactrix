import AppKit
import Foundation
import MatrixIntegration
import OSLog
import Observation

/// The signed-in accounts and which one is shown.
///
/// Every account syncs in the background; the UI shows the active one, exposed as `matrixClient`.
@MainActor @Observable
public final class AppState {
  public enum Restoration: Equatable {
    case pending
    /// Stored accounts have been restored; carries the active account's `storeID`.
    case restored(activeAccountID: String?)
  }

  public enum AccountError: LocalizedError {
    case alreadySignedIn(userID: String)

    public var errorDescription: String? {
      switch self {
      case .alreadySignedIn(let userID):
        "You're already signed in as \(userID)."
      }
    }
  }

  /// Signed-in accounts in display order.
  public private(set) var accounts: [MatrixClient] = [] {
    didSet { updateNotificationLabels() }
  }
  public private(set) var activeAccountID: String?
  private var hasRestored = false

  @ObservationIgnored private let accountStore: AccountStore
  @ObservationIgnored private var restoreTask: Task<Void, Never>?
  @ObservationIgnored private var lastAppliedDockUnreadCount: Int?

  /// Routes clicked notifications from every account.
  public let notificationRouter = NotificationRouter()

  public init() {
    accountStore = AccountStore()
    observeDockBadge()
  }

  /// The active account.
  public var matrixClient: MatrixClient? {
    accounts.first { $0.storeID == activeAccountID }
  }

  public var restoration: Restoration {
    hasRestored ? .restored(activeAccountID: activeAccountID) : .pending
  }

  /// Restores stored accounts and starts syncing them. Runs once; later calls wait for the first.
  public func restoreAccounts() async {
    if let restoreTask {
      await restoreTask.value
      return
    }
    let task = Task { await performRestore() }
    restoreTask = task
    await task.value
  }

  private func performRestore() async {
    let clients = await MatrixClient.restoreAll(accountStore: accountStore)
    accounts = clients
    let storedActive = accountStore.activeStoreID
    hasRestored = true
    activate(clients.first { $0.storeID == storedActive } ?? clients.first)
    for client in clients {
      startSync(client)
    }
  }

  /// Adds a newly signed-in account and makes it active.
  ///
  /// Signing in to an account that is already listed is rejected: the new session is signed out
  /// again so it doesn't linger as an extra device. If the listed account was signed out by the
  /// server, the new session replaces it instead.
  public func add(_ client: MatrixClient) async throws {
    if let existing = accounts.first(where: { $0.userID == client.userID }) {
      if existing.authenticationFailed {
        let index = accounts.firstIndex { $0 === existing }!
        await discard(existing)
        accounts.insert(client, at: min(index, accounts.count))
        accountStore.setOrder(accounts.map(\.storeID))
      } else {
        Logger.matrixClient.info("Rejecting duplicate sign-in for store \(client.storeID)")
        await discard(client)
        activate(existing)
        throw AccountError.alreadySignedIn(userID: client.userID)
      }
    } else {
      accounts.append(client)
    }
    activate(client)
    startSync(client)
  }

  public func activate(_ client: MatrixClient?) {
    activeAccountID = client?.storeID
    accountStore.activeStoreID = client?.storeID
  }

  /// Signs out of `client` and removes it, activating another account if it was active.
  public func remove(_ client: MatrixClient) async {
    accounts.removeAll { $0 === client }
    // Switch before signing out, which waits for the server.
    if client.storeID == activeAccountID {
      activate(accounts.first)
    }
    await discard(client)
  }

  /// Signs out of the active account.
  public func reset() async throws {
    guard let matrixClient else { return }
    await remove(matrixClient)
  }

  private func discard(_ client: MatrixClient) async {
    accounts.removeAll { $0 === client }
    do {
      try await client.reset()
    } catch {
      Logger.viewCycle.error("Failed to reset matrix client: \(error)")
    }
  }

  /// Opens the room of a clicked notification in `windowState`, switching to its account.
  public func showNotificationTarget(in windowState: WindowState) {
    // A click that launched the app arrives before accounts are restored; handle it afterwards.
    guard hasRestored, let target = notificationRouter.pendingTarget else { return }
    notificationRouter.pendingTarget = nil

    if let accountID = target.accountID {
      guard let account = accounts.first(where: { $0.storeID == accountID }) else {
        Logger.viewCycle.info("Ignoring notification from a removed account")
        return
      }
      activate(account)
      // Switch the window now so the room below isn't treated as the previous account's.
      windowState.showAccount(account.storeID, knownAccountIDs: Set(accounts.map(\.storeID)))
    }
    windowState.selectedRoomId = target.roomId
  }

  /// Names the receiving account in notifications once more than one account is signed in.
  private func updateNotificationLabels() {
    let showsLabels = accounts.count > 1
    for account in accounts {
      account.notifications.accountLabel = showsLabels ? account.userID : nil
    }
  }

  /// Shows the number of unread rooms across all accounts on the Dock icon.
  private func observeDockBadge() {
    let count = withObservationTracking {
      accounts.reduce(0) { $0 + $1.unreadRoomCount }
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observeDockBadge()
      }
    }

    guard count != lastAppliedDockUnreadCount else { return }
    NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    lastAppliedDockUnreadCount = count
  }

  private func startSync(_ client: MatrixClient) {
    Task {
      do {
        try await client.startSync()
      } catch {
        Logger.matrixClient.error("Failed to start sync: \(error)")
      }
    }
  }
}

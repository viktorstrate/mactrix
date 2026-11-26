import AppKit
import Foundation
import MatrixIntegration
import OSLog
import Observation

/// The signed-in accounts, and the windows showing them.
///
/// Every account syncs in the background. Each window shows one account of its own choosing,
/// holding a weak reference to its client.
@MainActor @Observable
public final class AppState {
  public enum Restoration: Equatable {
    case pending
    /// Stored accounts have been restored.
    case restored
  }

  public enum AccountError: LocalizedError {
    case alreadySignedIn(userID: String)

    public var errorDescription: String? {
      switch self {
      case .alreadySignedIn(let userID):
        String(localized: "You're already signed in as \(userID).")
      }
    }
  }

  /// Signed-in accounts in display order.
  public private(set) var accounts: [MatrixClient] = [] {
    didSet { updateNotificationLabels() }
  }
  /// The account of the most recently focused window, which new windows open on.
  public private(set) var lastFocusedAccountID: String?
  private var hasRestored = false
  /// Open windows, most recently focused first.
  @ObservationIgnored private var windows: [WeakWindowState] = []

  @ObservationIgnored private let accountStore: AccountStore
  @ObservationIgnored private var restoreTask: Task<Void, Never>?
  @ObservationIgnored private var lastAppliedDockUnreadCount: Int?

  /// Routes clicked notifications from every account.
  public let notificationRouter = NotificationRouter()

  public init() {
    // Before any account opens its stores.
    OpenFileLimit.raise()
    accountStore = AccountStore()
    observeDockBadge()
  }

  /// The account of the most recently focused window, which the Settings window shows.
  public var lastFocusedAccount: MatrixClient? {
    accounts.first { $0.storeID == lastFocusedAccountID }
  }

  /// The number of unread rooms across accounts other than `accountID`.
  public func unreadRoomCount(excludingAccountID accountID: String?) -> Int {
    accounts.reduce(0) { count, account in
      guard account.storeID != accountID, !account.authenticationFailed else { return count }
      return count + account.unreadRoomCount
    }
  }

  public var restoration: Restoration {
    hasRestored ? .restored : .pending
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
    setLastFocusedAccount(accountStore.lastFocusedStoreID)
    hasRestored = true
    for window in openWindows {
      attach(window)
    }
    for client in clients {
      startSync(client)
    }
  }

  /// Adds a newly signed-in account and shows it in `windowState`.
  ///
  /// Signing in to an account that is already listed is rejected: the new session is signed out
  /// again so it doesn't linger as an extra device. If the listed account was signed out by the
  /// server, the new session replaces it, in every window showing it.
  public func add(_ client: MatrixClient, in windowState: WindowState) async throws {
    if let existing = accounts.first(where: { $0.userID == client.userID }) {
      if existing.authenticationFailed {
        let index = accounts.firstIndex { $0 === existing }!
        let replacedWindows = openWindows.filter { $0.accountID == existing.storeID }
        await discard(existing)
        accounts.insert(client, at: min(index, accounts.count))
        accountStore.setOrder(accounts.map(\.storeID))
        for window in replacedWindows {
          show(client, in: window)
        }
      } else {
        Logger.matrixClient.info("Rejecting duplicate sign-in for store \(client.storeID)")
        await discard(client)
        show(existing, in: windowState)
        throw AccountError.alreadySignedIn(userID: client.userID)
      }
    } else {
      accounts.append(client)
    }
    show(client, in: windowState)
    startSync(client)
  }

  /// Shows `account` in `windowState`.
  public func show(_ account: MatrixClient, in windowState: WindowState) {
    windowState.showAccount(account, knownAccountIDs: Set(accounts.map(\.storeID)))
    if windowState === openWindows.first {
      setLastFocusedAccount(account.storeID)
    }
  }

  /// Signs out of `client` and removes it, switching the windows that showed it to another account.
  public func remove(_ client: MatrixClient) async {
    accounts.removeAll { $0 === client }
    // Switch before signing out, which waits for the server.
    if lastFocusedAccountID == client.storeID {
      setLastFocusedAccount(nil)
    }
    for window in openWindows where window.accountID == client.storeID {
      attach(window)
    }
    await discard(client)
  }

  /// Signs out of the account the Settings window shows.
  public func reset() async throws {
    guard let lastFocusedAccount else { return }
    await remove(lastFocusedAccount)
  }

  // MARK: Windows

  /// Records that `windowState` is open, and shows an account in it once accounts are restored.
  public func register(_ windowState: WindowState) {
    windows.removeAll { $0.value == nil || $0.value === windowState }
    windows.append(WeakWindowState(windowState))
    if hasRestored {
      attach(windowState)
    }
  }

  /// Records that `windowState` is the focused window.
  public func focus(_ windowState: WindowState) {
    windows.removeAll { $0.value == nil || $0.value === windowState }
    windows.insert(WeakWindowState(windowState), at: 0)
    if let accountID = windowState.accountID {
      setLastFocusedAccount(accountID)
    }
  }

  /// Open windows, most recently focused first.
  var openWindows: [WindowState] {
    windows.compactMap(\.value)
  }

  /// Connects `windowState` to its account's client, or to a fallback if its account is gone.
  ///
  /// A window keeps its own account if it still exists. Otherwise it shows the last focused
  /// window's account, then the first account.
  func attach(_ windowState: WindowState) {
    let account = Self.accountToShow(
      windowAccountID: windowState.accountID, lastFocusedAccountID: lastFocusedAccountID,
      accountIDs: accounts.map(\.storeID)
    ).flatMap { id in accounts.first { $0.storeID == id } }
    guard account !== windowState.matrixClient || account?.storeID != windowState.accountID else {
      return
    }
    windowState.showAccount(account, knownAccountIDs: Set(accounts.map(\.storeID)))
  }

  /// Which account a window shows, given the account it showed before.
  static func accountToShow(
    windowAccountID: String?, lastFocusedAccountID: String?, accountIDs: [String]
  ) -> String? {
    [windowAccountID, lastFocusedAccountID].lazy.compactMap { $0 }
      .first { accountIDs.contains($0) } ?? accountIDs.first
  }

  private func setLastFocusedAccount(_ storeID: String?) {
    let storeID =
      storeID.flatMap { id in accounts.contains { $0.storeID == id } ? id : nil }
      ?? accounts.first?.storeID
    lastFocusedAccountID = storeID
    accountStore.lastFocusedStoreID = storeID
    // Banners for the focused window's account would duplicate what is on screen.
    notificationRouter.activeAccountID = storeID
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
      // Switch the window now so the room below isn't treated as the previous account's.
      show(account, in: windowState)
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

private struct WeakWindowState {
  weak var value: WindowState?

  init(_ value: WindowState) {
    self.value = value
  }
}

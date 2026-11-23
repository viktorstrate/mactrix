import OSLog
import Observation
import UserNotifications

/// Receives clicks on notifications from every account.
///
/// The notification center has a single delegate, so this is owned by the app rather than by each
/// account's ``MatrixNotifications``.
@MainActor @Observable public final class NotificationRouter: NSObject {
  public struct Target: Equatable, Sendable {
    /// The `storeID` of the account that received the notification. `nil` for notifications
    /// posted by versions without multi-account support.
    public let accountID: String?
    public let roomId: String
  }

  /// The room of the most recently clicked notification, until the app has shown it.
  public var pendingTarget: Target?

  /// The `storeID` of the account shown in the app, whose notifications stay silent while the app
  /// is frontmost.
  @ObservationIgnored public var activeAccountID: String?

  public override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }
}

extension NotificationRouter: @MainActor UNUserNotificationCenterDelegate {
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    guard let roomId = userInfo[MatrixNotifications.UserInfoKey.roomId] as? String else { return }
    let accountID = userInfo[MatrixNotifications.UserInfoKey.accountID] as? String
    Logger.notification.info("Notification clicked for room \(roomId) in store \(accountID ?? "?")")
    pendingTarget = Target(accountID: accountID, roomId: roomId)
  }

  /// Shows notifications from accounts other than the active one while the app is frontmost,
  /// since their rooms aren't visible. macOS would otherwise hide them.
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let accountID =
      notification.request.content.userInfo[MatrixNotifications.UserInfoKey.accountID] as? String
    return Self.foregroundPresentation(forAccountID: accountID, activeAccountID: activeAccountID)
  }

  static func foregroundPresentation(forAccountID accountID: String?, activeAccountID: String?)
    -> UNNotificationPresentationOptions
  {
    guard let accountID, accountID != activeAccountID else { return [] }
    return [.banner, .list, .sound]
  }
}

import ContactLinking
import MatrixRustSDK
import OSLog
import UserNotifications

// This class is Sendable because MatrixRustSDK.SyncNotificationListener requires it to be so
@MainActor @Observable public final class MatrixNotifications: NSObject, Sendable {
  enum UserInfoKey {
    static let roomId = "roomId"
    static let accountID = "accountID"
  }

  /// The `storeID` of the account these notifications belong to.
  let accountID: String
  /// Names the account in notifications; set when more than one account is signed in.
  public var accountLabel: String?

  typealias NotificationEvent = (item: MatrixRustSDK.NotificationItem, roomId: String)

  @ObservationIgnored private let notificationContinuation:
    AsyncStream<NotificationEvent>.Continuation
  @ObservationIgnored private var streamTask: Task<Void, Never>?

  init(accountID: String) {
    self.accountID = accountID
    let (stream, continuation) = AsyncStream<NotificationEvent>.makeStream()
    notificationContinuation = continuation

    super.init()

    streamTask = Task { [weak self] in
      for await (notification, roomId) in stream {
        guard let self else { break }
        await self.sendNotification(notification: notification, roomId: roomId)
      }
    }
  }
}

extension MatrixNotifications: MatrixRustSDK.SyncNotificationListener {
  public nonisolated func onNotification(
    notification: MatrixRustSDK.NotificationItem, roomId: String
  ) {
    notificationContinuation.yield((notification, roomId))
  }
}

extension MatrixNotifications {
  func sendNotification(notification: MatrixRustSDK.NotificationItem, roomId: String) async {
    do {
      let success = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .badge, .sound])
      guard success else {
        Logger.notification.warning("user rejected notification request")
        return
      }
    } catch {
      Logger.notification.error("failed to request notification permissions: \(error)")
      return
    }

    Logger.notification.debug("sending notification from room \(roomId)")

    let content = UNMutableNotificationContent()
    content.title = notificationTitle(for: notification)
    if let accountLabel {
      content.subtitle = accountLabel
      content.body = notificationBody(for: notification)
    } else {
      content.subtitle = notificationBody(for: notification)
    }
    content.sound = UNNotificationSound.default
    content.interruptionLevel = .timeSensitive
    content.threadIdentifier = accountID
    content.userInfo = [UserInfoKey.roomId: roomId, UserInfoKey.accountID: accountID]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: trigger)

    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      Logger.notification.error("failed to schedule notification: \(error)")
    }
  }

  func notificationTitle(for notification: NotificationItem) -> String {
    switch notification.event {
    case .invite(let sender):
      let inviter = ContactDirectory.shared.resolvedName(userID: sender, matrixName: nil)
      return String(localized: "\(inviter) invited you to a room")
    case .timeline(let event):
      let sender = ContactDirectory.shared.resolvedName(
        userID: event.senderId(), matrixName: notification.senderInfo.displayName)
      let roomName = notification.roomInfo.displayName
      return "\(sender) (\(roomName))"
    }
  }

  func notificationBody(for notification: NotificationItem) -> String {
    switch notification.event {
    case .invite(sender: _):
      return String(localized: "Room \(notification.roomInfo.displayName)")
    case .timeline(let event):
      do {
        switch try event.content() {
        case .messageLike(content: let msgLike):
          switch msgLike {
          case .callAnswer:
            return String(localized: "Call answered")
          case .callInvite:
            return String(localized: "Call invitation")
          case .rtcNotification:
            return String(localized: "RTC Notification")
          case .callHangup:
            return String(localized: "Call hang up")
          case .callCandidates:
            return String(localized: "Call candidates")
          case .keyVerificationReady:
            return String(localized: "Key verification ready")
          case .keyVerificationStart:
            return String(localized: "Key verification start")
          case .keyVerificationCancel:
            return String(localized: "Key verification cancel")
          case .keyVerificationAccept:
            return String(localized: "Key verification accept")
          case .keyVerificationKey:
            return String(localized: "Key verification key")
          case .keyVerificationMac:
            return String(localized: "Key verification mac")
          case .keyVerificationDone:
            return String(localized: "Key verification done")
          case .poll(let question):
            return String(localized: "Asked \(question)")
          case .reactionContent:
            return String(localized: "Reaction content")
          case .roomEncrypted:
            return String(localized: "Room encrypted")
          case .roomMessage(let messageType, _):
            switch messageType {
            case .emote:
              return String(localized: "Emote")
            case .image:
              return String(localized: "Image")
            case .audio:
              return String(localized: "Audio")
            case .video:
              return String(localized: "Video")
            case .file:
              return String(localized: "File")
            case .gallery:
              return String(localized: "Gallery")
            case .notice:
              return String(localized: "Notice")
            case .text(let content):
              return content.body
            case .location:
              return String(localized: "Location")
            case .other(let msgtype, let body):
              return "\(msgtype): \(body)"
            }
          case .roomRedaction:
            return String(localized: "Message redacted")
          case .sticker:
            return String(localized: "Sent a sticker")
          case .beacon:
            return String(localized: "Beacon")
          }
        case .state(content:):
          return String(localized: "State change")
        }
      } catch {
        return error.localizedDescription
      }
    }
  }
}

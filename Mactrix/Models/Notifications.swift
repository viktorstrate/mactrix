import MatrixRustSDK
import OSLog
import UserNotifications

@MainActor @Observable
final class MatrixNotifications: NSObject {
    var selectedRoomId: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
}

extension MatrixNotifications: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let roomId = response.notification.request.content.userInfo["roomId"] as? String
        Logger.notification.info("Notification delegate didReceive: \(roomId ?? "<no room id>")")
        selectedRoomId = roomId
    }
}

extension MatrixNotifications: MatrixRustSDK.SyncNotificationListener {
    nonisolated func onNotification(notification: MatrixRustSDK.NotificationItem, roomId: String) {
        Task { @MainActor in
            let success = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            guard success else {
                Logger.notification.warning("user rejected notification request")
                return
            }

            Logger.notification.debug("sending notification from room \(roomId)")

            let content = UNMutableNotificationContent()
            content.title = notificationTitle(for: notification)
            content.subtitle = notificationBody(for: notification)
            content.sound = UNNotificationSound.default
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["roomId": roomId]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Logger.notification.error("failed to schedule notification \(error)")
            }
        }
    }

    func notificationTitle(for notification: NotificationItem) -> String {
        switch notification.event {
        case let .invite(sender: sender):
            return "\(sender) invited you to a room"
        case let .timeline(event: event):
            let sender = notification.senderInfo.displayName ?? event.senderId()
            let roomName = notification.roomInfo.displayName
            return "\(sender) (\(roomName))"
        }
    }

    func notificationBody(for notification: NotificationItem) -> String {
        switch notification.event {
        case .invite(sender: _):
            return "Room \(notification.roomInfo.displayName)"
        case let .timeline(event: event):
            do {
                switch try event.content() {
                case let .messageLike(content: msgLike):
                    switch msgLike {
                    case .callAnswer:
                        return "Call answered"
                    case .callInvite:
                        return "Call invitation"
                    case .rtcNotification:
                        return "RTC Notification"
                    case .callHangup:
                        return "Call hang up"
                    case .callCandidates:
                        return "Call candidates"
                    case .keyVerificationReady:
                        return "Key verification ready"
                    case .keyVerificationStart:
                        return "Key verification start"
                    case .keyVerificationCancel:
                        return "Key verification cancel"
                    case .keyVerificationAccept:
                        return "Key verification accept"
                    case .keyVerificationKey:
                        return "Key verification key"
                    case .keyVerificationMac:
                        return "Key verification mac"
                    case .keyVerificationDone:
                        return "Key verification done"
                    case let .poll(question):
                        return "Asked \(question)"
                    case .reactionContent:
                        return "Reaction content"
                    case .roomEncrypted:
                        return "Room encrypted"
                    case let .roomMessage(messageType, _):
                        switch messageType {
                        case .emote:
                            return "Emote"
                        case .image:
                            return "Image"
                        case .audio:
                            return "Audio"
                        case .video:
                            return "Video"
                        case .file:
                            return "File"
                        case .gallery:
                            return "Gallery"
                        case .notice:
                            return "Notice"
                        case let .text(content):
                            return content.body
                        case .location:
                            return "Location"
                        case let .other(msgtype, body):
                            return "\(msgtype): \(body)"
                        }
                    case .roomRedaction:
                        return "Message redacted"
                    case .sticker:
                        return "Sent a sticker"
                    }
                case .state(content:):
                    return "State change"
                }
            } catch {
                return error.localizedDescription
            }
        }
    }
}

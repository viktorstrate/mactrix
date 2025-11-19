import Foundation
import MatrixRustSDK

class RoomMock: RoomProtocol {
    struct MockError: Error {}

    func activeMembersCount() -> UInt64 {
        return 2
    }

    func activeRoomCallParticipants() -> [String] {
        return []
    }

    func alternativeAliases() -> [String] {
        return []
    }

    func applyPowerLevelChanges(changes _: MatrixRustSDK.RoomPowerLevelChanges) async throws {}

    func avatarUrl() -> String? {
        return nil
    }

    func banUser(userId _: String, reason _: String?) async throws {}

    func canonicalAlias() -> String? {
        return nil
    }

    func clearComposerDraft(threadRoot _: String?) async throws {}

    func clearEventCacheStorage() async throws {}

    func declineCall(rtcNotificationEventId _: String) async throws {}

    func discardRoomKey() async throws {}

    func displayName() -> String? {
        return "Room Name"
    }

    func edit(eventId _: String, newContent _: MatrixRustSDK.RoomMessageEventContentWithoutRelation) async throws {}

    func enableEncryption() async throws {}

    func enableSendQueue(enable _: Bool) {}

    func encryptionState() -> MatrixRustSDK.EncryptionState {
        return .encrypted
    }

    func fetchThreadSubscription(threadRootEventId _: String) async throws -> MatrixRustSDK.ThreadSubscription? {
        return nil
    }

    func forget() async throws {}

    func getPowerLevels() async throws -> MatrixRustSDK.RoomPowerLevels {
        return .init(noPointer: .init())
    }

    func getRoomVisibility() async throws -> MatrixRustSDK.RoomVisibility {
        return .private
    }

    func hasActiveRoomCall() -> Bool {
        return false
    }

    func heroes() -> [MatrixRustSDK.RoomHero] {
        return []
    }

    func id() -> String {
        return "ROOM_ID"
    }

    func ignoreDeviceTrustAndResend(devices _: [String: [String]], sendHandle _: MatrixRustSDK.SendHandle) async throws {}

    func ignoreUser(userId _: String) async throws {}

    func inviteUserById(userId _: String) async throws {}

    func invitedMembersCount() -> UInt64 {
        return 1
    }

    func inviter() async throws -> MatrixRustSDK.RoomMember? {
        return nil
    }

    func isDirect() async -> Bool {
        return false
    }

    func isEncrypted() async -> Bool {
        return true
    }

    func isPublic() -> Bool? {
        return false
    }

    func isSendQueueEnabled() -> Bool {
        return false
    }

    func isSpace() -> Bool {
        return false
    }

    func join() async throws {}

    func joinedMembersCount() -> UInt64 {
        return 2
    }

    func kickUser(userId _: String, reason _: String?) async throws {}

    func latestEncryptionState() async throws -> MatrixRustSDK.EncryptionState {
        return .encrypted
    }

    func latestEvent() async -> MatrixRustSDK.EventTimelineItem? {
        return nil
    }

    func leave() async throws {}

    func loadComposerDraft(threadRoot _: String?) async throws -> MatrixRustSDK.ComposerDraft? {
        return nil
    }

    func loadOrFetchEvent(eventId _: String) async throws -> MatrixRustSDK.TimelineEvent {
        return TimelineEvent(noPointer: .init())
    }

    func markAsRead(receiptType _: MatrixRustSDK.ReceiptType) async throws {}

    func matrixToEventPermalink(eventId: String) async throws -> String {
        return "PERMA_\(eventId)"
    }

    func matrixToPermalink() async throws -> String {
        return "ROOM_PERMA"
    }

    func member(userId _: String) async throws -> MatrixRustSDK.RoomMember {
        throw MockError()
    }

    func memberAvatarUrl(userId _: String) async throws -> String? {
        return nil
    }

    func memberDisplayName(userId _: String) async throws -> String? {
        return nil
    }

    func memberWithSenderInfo(userId _: String) async throws -> MatrixRustSDK.RoomMemberWithSenderInfo {
        throw MockError()
    }

    func members() async throws -> MatrixRustSDK.RoomMembersIterator {
        throw MockError()
    }

    func membersNoSync() async throws -> MatrixRustSDK.RoomMembersIterator {
        throw MockError()
    }

    func membership() -> MatrixRustSDK.Membership {
        return .joined
    }

    func newLatestEvent() async -> MatrixRustSDK.LatestEventValue {
        return .none
    }

    func ownUserId() -> String {
        return "USER_ID"
    }

    func predecessorRoom() -> MatrixRustSDK.PredecessorRoom? {
        return nil
    }

    func previewRoom(via _: [String]) async throws -> MatrixRustSDK.RoomPreview {
        throw MockError()
    }

    func publishRoomAliasInRoomDirectory(alias _: String) async throws -> Bool {
        return false
    }

    func rawName() -> String? {
        return nil
    }

    func redact(eventId _: String, reason _: String?) async throws {}

    func removeAvatar() async throws {}

    func removeRoomAliasFromRoomDirectory(alias _: String) async throws -> Bool {
        return false
    }

    func reportContent(eventId _: String, score _: Int32?, reason _: String?) async throws {}

    func reportRoom(reason _: String) async throws {}

    func resetPowerLevels() async throws -> MatrixRustSDK.RoomPowerLevels {
        throw MockError()
    }

    func roomEventsDebugString() async throws -> [String] {
        return []
    }

    func roomInfo() async throws -> MatrixRustSDK.RoomInfo {
        throw MockError()
    }

    func saveComposerDraft(draft _: MatrixRustSDK.ComposerDraft, threadRoot _: String?) async throws {}

    func sendLiveLocation(geoUri _: String) async throws {}

    func sendRaw(eventType _: String, content _: String) async throws {}

    func setIsFavourite(isFavourite _: Bool, tagOrder _: Double?) async throws {}

    func setIsLowPriority(isLowPriority _: Bool, tagOrder _: Double?) async throws {}

    func setName(name _: String) async throws {}

    func setThreadSubscription(threadRootEventId _: String, subscribed _: Bool) async throws {}

    func setTopic(topic _: String) async throws {}

    func setUnreadFlag(newValue _: Bool) async throws {}

    func startLiveLocationShare(durationMillis _: UInt64) async throws {}

    func stopLiveLocationShare() async throws {}

    func subscribeToCallDeclineEvents(rtcNotificationEventId _: String, listener _: any MatrixRustSDK.CallDeclineListener) throws -> MatrixRustSDK.TaskHandle {
        throw MockError()
    }

    func subscribeToIdentityStatusChanges(listener _: any MatrixRustSDK.IdentityStatusChangeListener) async throws -> MatrixRustSDK.TaskHandle {
        throw MockError()
    }

    func subscribeToKnockRequests(listener _: any MatrixRustSDK.KnockRequestsListener) async throws -> MatrixRustSDK.TaskHandle {
        throw MockError()
    }

    func subscribeToLiveLocationShares(listener _: any MatrixRustSDK.LiveLocationShareListener) -> MatrixRustSDK.TaskHandle {
        return TaskHandle(noPointer: .init())
    }

    func subscribeToRoomInfoUpdates(listener _: any MatrixRustSDK.RoomInfoListener) -> MatrixRustSDK.TaskHandle {
        return TaskHandle(noPointer: .init())
    }

    func subscribeToSendQueueUpdates(listener _: any MatrixRustSDK.SendQueueListener) async throws -> MatrixRustSDK.TaskHandle {
        throw MockError()
    }

    func subscribeToTypingNotifications(listener _: any MatrixRustSDK.TypingNotificationsListener) -> MatrixRustSDK.TaskHandle {
        return TaskHandle(noPointer: .init())
    }

    func successorRoom() -> MatrixRustSDK.SuccessorRoom? {
        return nil
    }

    func suggestedRoleForUser(userId _: String) async throws -> MatrixRustSDK.RoomMemberRole {
        return .user
    }

    func timeline() async throws -> MatrixRustSDK.Timeline {
        throw MockError()
    }

    func timelineWithConfiguration(configuration _: MatrixRustSDK.TimelineConfiguration) async throws -> MatrixRustSDK.Timeline {
        throw MockError()
    }

    func topic() -> String? {
        return "The room topic"
    }

    func typingNotice(isTyping _: Bool) async throws {}

    func unbanUser(userId _: String, reason _: String?) async throws {}

    func updateCanonicalAlias(alias _: String?, altAliases _: [String]) async throws {}

    func updateHistoryVisibility(visibility _: MatrixRustSDK.RoomHistoryVisibility) async throws {}

    func updateJoinRules(newRule _: MatrixRustSDK.JoinRule) async throws {}

    func updatePowerLevelsForUsers(updates _: [MatrixRustSDK.UserPowerLevelUpdate]) async throws {}

    func updateRoomVisibility(visibility _: MatrixRustSDK.RoomVisibility) async throws {}

    func uploadAvatar(mimeType _: String, data _: Data, mediaInfo _: MatrixRustSDK.ImageInfo?) async throws {}

    func withdrawVerificationAndResend(userIds _: [String], sendHandle _: MatrixRustSDK.SendHandle) async throws {}
}

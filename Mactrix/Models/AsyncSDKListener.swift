import Foundation
import MatrixRustSDK
import OSLog

final class AsyncSDKListener<Element: Sendable>: AsyncSequence, Sendable {
    typealias Element = Element
    typealias AsyncIterator = AsyncStream<Element>.Iterator

    private let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation

    init() {
        let (s, c) = AsyncStream<Element>.makeStream()
        stream = s
        continuation = c
    }

    func publishValue(_ element: Element) {
        continuation.yield(element)
    }

    func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        return stream.makeAsyncIterator()
    }
}

extension AsyncSDKListener: TypingNotificationsListener where Element == [String] {
    func call(typingUserIds: [String]) {
        publishValue(typingUserIds)
    }
}

extension AsyncSDKListener: RoomDirectorySearchEntriesListener where Element == [MatrixRustSDK.RoomDirectorySearchEntryUpdate] {
    func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomDirectorySearchEntryUpdate]) {
        publishValue(roomEntriesUpdate)
    }
}

extension AsyncSDKListener: SpaceRoomListPaginationStateListener where Element == MatrixRustSDK.SpaceRoomListPaginationState {
    func onUpdate(paginationState: MatrixRustSDK.SpaceRoomListPaginationState) {
        publishValue(paginationState)
    }
}

extension AsyncSDKListener: SpaceRoomListEntriesListener where Element == [MatrixRustSDK.SpaceListUpdate] {
    func onUpdate(rooms: [MatrixRustSDK.SpaceListUpdate]) {
        publishValue(rooms)
    }
}

extension AsyncSDKListener: SpaceRoomListSpaceListener where Element == MatrixRustSDK.SpaceRoom? {
    func onUpdate(space: MatrixRustSDK.SpaceRoom?) {
        publishValue(space)
    }
}

extension AsyncSDKListener: SpaceServiceJoinedSpacesListener where Element == [MatrixRustSDK.SpaceListUpdate] {
    func onUpdate(roomUpdates: [MatrixRustSDK.SpaceListUpdate]) {
        publishValue(roomUpdates)
    }
}

extension AsyncSDKListener: TimelineListener where Element == [MatrixRustSDK.TimelineDiff] {
    func onUpdate(diff: [TimelineDiff]) {
        publishValue(diff)
    }
}

extension AsyncSDKListener: PaginationStatusListener where Element == MatrixRustSDK.RoomPaginationStatus {
    func onUpdate(status: MatrixRustSDK.RoomPaginationStatus) {
        publishValue(status)
    }
}

extension AsyncSDKListener: RoomInfoListener where Element == MatrixRustSDK.RoomInfo {
    func call(roomInfo: MatrixRustSDK.RoomInfo) {
        publishValue(roomInfo)
    }
}

extension AsyncSDKListener: RoomListEntriesListener where Element == [RoomListEntriesUpdate] {
    func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomListEntriesUpdate]) {
        publishValue(roomEntriesUpdate)
    }
}

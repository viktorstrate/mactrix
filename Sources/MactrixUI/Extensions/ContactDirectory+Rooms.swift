import ContactLinking
import MatrixProtocols

extension ContactDirectory {
  /// The title to show for a room, using the linked contact's name for direct chats.
  public func roomTitle(roomName: String?, roomInfo: (any RoomInfo)?) -> String? {
    if let userID = roomInfo?.directUserId, let contactName = contactName(for: userID) {
      return contactName
    }
    return roomName
  }
}

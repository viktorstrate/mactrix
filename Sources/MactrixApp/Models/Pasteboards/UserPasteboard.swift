import AppKit

extension NSPasteboard.PasteboardType {
  static let mactrixUser = Self("org.mactrix.user")
}

struct UserDragPayload: Codable {
  let userID: String
  let username: String

  init(
    userID: String,
    username: String,
  ) {
    self.userID = userID
    self.username = username
  }

  func makePasteboardItem() throws -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setData(
      try JSONEncoder().encode(self),
      forType: .mactrixUser
    )
    return item
  }

  static func read(from pasteboard: NSPasteboard) -> Self? {
    guard
      let data = pasteboard.data(forType: .mactrixUser),
      let payload = try? JSONDecoder().decode(Self.self, from: data)
    else {
      return nil
    }

    return payload
  }
}

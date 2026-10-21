import AppKit

extension NSPasteboard.PasteboardType {
  public static let mactrixUser = Self("org.mactrix.user")
}

public struct UserDragPayload: Codable {
  public let userID: String
  public let username: String

  public init(
    userID: String,
    username: String,
  ) {
    self.userID = userID
    self.username = username
  }

  public func makePasteboardItem() throws -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setData(
      try JSONEncoder().encode(self),
      forType: .mactrixUser
    )
    var components = URLComponents()
    components.scheme = "https"
    components.host = "matrix.to"
    components.path = "/"

    guard
      let encodedUserID = userID.addingPercentEncoding(
        withAllowedCharacters: CharacterSet.urlFragmentAllowed)
    else { throw URLError(.badURL) }
    components.percentEncodedFragment = "/" + encodedUserID
    guard let permalink = components.url else { throw URLError(.badURL) }

    let url = permalink.absoluteString
    let html = "<a href=\"\(Self.escapeHTML(url))\">\(Self.escapeHTML(username))</a>"
    item.setString(url, forType: .URL)
    item.setString(html, forType: .html)
    item.setString(userID, forType: .string)
    return item
  }

  public func makeItemProvider() throws -> NSItemProvider {
    let item = try makePasteboardItem()
    let provider = NSItemProvider()
    provider.suggestedName = username

    for type in item.types {
      guard let data = item.data(forType: type) else { continue }
      // Capture bytes now; provider callbacks may run outside the UI thread.
      provider.registerDataRepresentation(
        forTypeIdentifier: type.rawValue,
        visibility: .all
      ) { completion in
        completion(data, nil)
        return nil
      }
    }

    return provider
  }

  private static func escapeHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  public static func read(from pasteboard: NSPasteboard) -> Self? {
    guard
      let data = pasteboard.data(forType: .mactrixUser),
      let payload = try? JSONDecoder().decode(Self.self, from: data)
    else {
      return nil
    }

    return payload
  }
}

import AppKit

extension NSPasteboard.PasteboardType {
  public static let mactrixUser = Self("org.mactrix.user")
}

public struct UserDragPayload: Codable {
  public let userID: String
  public let username: String
  public let avatarUrl: String?

  public init(
    userID: String,
    username: String,
    avatarUrl: String? = nil,
  ) {
    self.userID = userID
    self.username = username
    self.avatarUrl = avatarUrl
  }

  public var url: String? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "matrix.to"
    components.path = "/"

    guard
      let encodedUserID = userID.addingPercentEncoding(
        withAllowedCharacters: CharacterSet.urlFragmentAllowed)
    else { return nil }
    components.percentEncodedFragment = "/" + encodedUserID
    guard let permalink = components.url else { return nil }

    return permalink.absoluteString
  }

  public var htmlLink: String? {
    guard let url else { return nil }
    return "<a href=\"\(Self.escapeHTML(url))\">\(Self.escapeHTML(username))</a>"
  }

  public var markdownLink: String? {
    guard let url else { return nil }
    return "[\(Self.escapeMarkdownBrackets(username))](\(Self.escapeHTML(url)))"
  }

  public func makePasteboardItem() throws -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setData(
      try JSONEncoder().encode(self),
      forType: .mactrixUser
    )

    if let url {
      item.setString(url, forType: .URL)
    }

    if let htmlLink {
      item.setString(htmlLink, forType: .html)
    }

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

  private static func escapeMarkdownBrackets(_ value: String) -> String {
    Self.escapeHTML(value)
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
      .replacingOccurrences(of: "(", with: "\\(")
      .replacingOccurrences(of: ")", with: "\\)")
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

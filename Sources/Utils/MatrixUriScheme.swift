import Foundation

public enum MatrixUriError: LocalizedError {
  case parserError(reason: LocalizedStringResource)

  public var errorDescription: String? {
    switch self {
    case .parserError(let reason):
      return "failed to parse matrix uri: \(reason)"
    }
  }
}

public struct MatrixUriScheme: Hashable, Codable, Sendable {
  public let kind: Kind
  public let routingVia: [String]
  public let action: Action?
  public let event: String?

  public enum Kind: Hashable, Codable, Sendable {
    case roomId(String)
    case roomAlias(String)
    case user(String)
  }

  public enum Action: Hashable, Codable, Sendable {
    case join, chat
  }

  public init(parseMatrixToUrl matrixToUrl: String) throws(MatrixUriError) {
    let matrixToPrefix = "https://matrix.to/#/"
    guard matrixToUrl.hasPrefix(matrixToPrefix) else {
      throw .parserError(reason: "invalid matrix.to url")
    }

    // Historical matrix.to links can contain an unescaped room-alias sigil.
    let encodedFragment = matrixToUrl.dropFirst(matrixToPrefix.count)
      .replacingOccurrences(of: "#", with: "%23")
    guard
      let components = URLComponents(
        string: matrixToPrefix + encodedFragment, encodingInvalidCharacters: false),
      let fragment = components.percentEncodedFragment
    else {
      throw .parserError(reason: "invalid matrix.to url")
    }

    // fragment example: /!room:example.org/$event?via=elsewhere.ca
    let parts = fragment.dropFirst().split(
      separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let path = parts[0].split(separator: "/", omittingEmptySubsequences: false)
    guard path.count <= 2 else {
      throw .parserError(reason: "invalid matrix.to path")
    }

    let id = try Self.urlDecode(path[0])
    switch id.unicodeScalars.first {
    case "@":
      self.kind = .user(try Self.validateIdentifier(id, requiresServerName: true))
    case "#":
      self.kind = .roomAlias(try Self.validateIdentifier(id, requiresServerName: true))
    case "!":
      self.kind = .roomId(try Self.validateIdentifier(id))
    default:
      throw .parserError(reason: "invalid matrix.to identifier")
    }

    if path.count == 2 {
      let event = try Self.urlDecode(path[1])
      guard id.unicodeScalars.first != "@", event.unicodeScalars.first == "$" else {
        // users can not reference events
        throw .parserError(reason: "invalid matrix.to event")
      }
      self.event = try Self.validateIdentifier(event)
    } else {
      self.event = nil
    }

    (routingVia, action) = try Self.parseQuery(parts.count == 2 ? parts[1] : nil, kind: kind)
  }

  public init(parseUrl url: String) throws(MatrixUriError) {
    if url.hasPrefix("https://matrix.to/") {
      self = try Self(parseMatrixToUrl: url)
      return
    }

    guard let components = URLComponents(string: url, encodingInvalidCharacters: false),
      components.scheme?.lowercased() == "matrix"
    else {
      throw .parserError(reason: "invalid matrix uri")
    }

    var path = components.percentEncodedPath[...]
    if components.percentEncodedHost != nil {
      guard path.hasPrefix("/") else {
        throw .parserError(reason: "missing authority separator")
      }
      path = path.dropFirst()
    } else if path.hasPrefix("/") {
      throw .parserError(reason: "unexpected leading slash")
    }

    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 2 || segments.count == 4,
      !segments.contains(where: { $0.isEmpty })
    else {
      throw .parserError(reason: "invalid matrix path")
    }
    let type = try Self.urlDecode(segments[0]).lowercased()
    let id = try Self.urlDecode(segments[1])

    // The path contains the ID body, which can itself start with a sigil.
    switch type {
    case "roomid":
      self.kind = .roomId(try Self.validateIdentifier("!" + id))
    case "r", "room":
      self.kind = .roomAlias(try Self.validateIdentifier("#" + id, requiresServerName: true))
    case "u", "user":
      self.kind = .user(try Self.validateIdentifier("@" + id, requiresServerName: true))
    default:
      throw .parserError(reason: "invalid type \(type)")
    }

    if segments.count == 4 {
      let eventType = try Self.urlDecode(segments[2]).lowercased()
      // Alias permalinks are deprecated but still accepted for compatibility.
      if case .user = kind {
        throw .parserError(reason: "invalid event descriptor")
      }
      guard eventType == "e" || eventType == "event" else {
        throw .parserError(reason: "invalid event descriptor")
      }
      self.event = try Self.validateIdentifier("$" + Self.urlDecode(segments[3]))
    } else {
      self.event = nil
    }

    (routingVia, action) = try Self.parseQuery(components.percentEncodedQuery?[...], kind: kind)
  }

  private static func urlDecode(_ component: Substring) throws(MatrixUriError) -> String {
    guard let decoded = component.removingPercentEncoding else {
      throw .parserError(reason: "invalid percent encoding")
    }
    return decoded
  }

  private static func validateIdentifier(_ id: String, requiresServerName: Bool = false)
    throws(MatrixUriError) -> String
  {
    guard (2...255).contains(id.utf8.count), !id.utf8.contains(0) else {
      throw .parserError(reason: "invalid identifier")
    }
    // Keep historical user localparts and treat room and event IDs as opaque.
    if requiresServerName {
      let scalars = id.unicodeScalars
      guard let separator = scalars.firstIndex(of: ":"),
        Self.isServerName(String(scalars[scalars.index(after: separator)...]))
      else {
        throw .parserError(reason: "invalid identifier server name")
      }
    }
    return id
  }

  private static func isServerName(_ server: String) -> Bool {
    // Check the URI structure and leave address validation to the Matrix SDK.
    guard
      let components = URLComponents(
        string: "https://" + server, encodingInvalidCharacters: false),
      let host = components.percentEncodedHost, !host.isEmpty
    else { return false }

    return components.percentEncodedUser == nil && components.percentEncodedPassword == nil
      && components.percentEncodedPath.isEmpty && components.percentEncodedQuery == nil
      && components.percentEncodedFragment == nil
  }

  private static func parseQuery(_ query: Substring?, kind: Kind)
    throws(MatrixUriError) -> ([String], Action?)
  {
    var routingVia = [String]()
    var action: Action?

    // Split before decoding, and do not interpret '+' as form-encoded whitespace.
    for item in query?.split(separator: "&") ?? [] {
      let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = try urlDecode(pair[0]).lowercased()
      guard pair.count == 2 else { continue }
      let value = try urlDecode(pair[1])

      switch key {
      case "via" where !value.isEmpty:
        guard Self.isServerName(value) else {
          throw .parserError(reason: "invalid routing server name")
        }
        routingVia.append(value)
      case "action":
        // MSC2312 takes the last action item, even if it is not recognized.
        switch value.lowercased() {
        case "join": action = .join
        case "chat": action = .chat
        default: action = nil
        }
      default:
        break
      }
    }

    switch (kind, action) {
    case (.user, .join), (.roomId, .chat), (.roomAlias, .chat):
      action = nil
    default:
      break
    }
    return (routingVia, action)
  }

  public init(kind: Kind) {
    self.kind = kind
    routingVia = []
    action = nil
    event = nil
  }
}

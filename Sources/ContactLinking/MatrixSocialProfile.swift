import Contacts
import Foundation

/// Helpers for storing a Matrix user ID in a contact's social profile field.
///
/// A link is stored as a `CNSocialProfile` with the service `Matrix`, the Matrix user ID as
/// username and a matrix.to permalink as URL, so it shows up in Contacts.app and syncs with
/// the rest of the contact.
public enum MatrixSocialProfile {
  public static let service = "Matrix"

  private static let matrixToPrefix = "https://matrix.to/#/"
  private static let matrixUriPrefix = "matrix:u/"

  /// Returns the Matrix user ID a social profile refers to, or `nil` if it isn't a Matrix profile.
  public static func userID(from profile: CNSocialProfile) -> String? {
    userID(service: profile.service, username: profile.username, urlString: profile.urlString)
  }

  public static func userID(service: String?, username: String?, urlString: String?) -> String? {
    let isMatrixService =
      service?.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare(Self.service) == .orderedSame

    if isMatrixService, let username, let userID = normalize(username) {
      return userID
    }

    if let urlString, let userID = userID(fromURLString: urlString) {
      return userID
    }

    return nil
  }

  /// Creates the social profile that links a contact to `userID`.
  public static func makeProfile(userID: String) -> CNSocialProfile {
    let userID = normalize(userID) ?? userID
    return CNSocialProfile(
      urlString: matrixToPrefix + userID,
      username: userID,
      userIdentifier: nil,
      service: service
    )
  }

  /// Normalises a Matrix user ID to `@localpart:server` with a lowercased server name.
  ///
  /// Returns `nil` if the string doesn't look like a Matrix user ID.
  public static func normalize(_ rawValue: String) -> String? {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.hasPrefix("@") {
      value = "@" + value
    }

    guard let separator = value.firstIndex(of: ":") else { return nil }
    let localpart = value[value.index(after: value.startIndex)..<separator]
    let server = value[value.index(after: separator)...]
    guard !localpart.isEmpty, !server.isEmpty,
      !localpart.contains(where: \.isWhitespace), !server.contains(where: \.isWhitespace)
    else { return nil }

    return "@\(localpart):\(server.lowercased())"
  }

  private static func userID(fromURLString urlString: String) -> String? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

    let candidate: Substring
    if trimmed.lowercased().hasPrefix(matrixToPrefix) {
      candidate = trimmed.dropFirst(matrixToPrefix.count)
    } else if trimmed.lowercased().hasPrefix(matrixUriPrefix) {
      candidate = trimmed.dropFirst(matrixUriPrefix.count)
    } else {
      return nil
    }

    let identifier = candidate.prefix(while: { $0 != "?" && $0 != "/" })
    let decoded = String(identifier).removingPercentEncoding ?? String(identifier)

    // matrix.to links must point at a user ("@…"); matrix: URIs omit the sigil.
    if trimmed.lowercased().hasPrefix(matrixToPrefix), !decoded.hasPrefix("@") {
      return nil
    }
    return normalize(decoded)
  }
}

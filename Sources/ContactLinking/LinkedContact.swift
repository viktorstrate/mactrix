import Foundation

/// A system contact that is linked to a Matrix user.
public struct LinkedContact: Sendable, Hashable {
  public let identifier: String
  /// The formatted full name, or the organisation name for company contacts.
  public let fullName: String?
  public let nickname: String?
  public let thumbnailData: Data?

  public init(identifier: String, fullName: String?, nickname: String?, thumbnailData: Data?) {
    self.identifier = identifier
    self.fullName = fullName.flatMap(Self.nonEmpty)
    self.nickname = nickname.flatMap(Self.nonEmpty)
    self.thumbnailData = thumbnailData
  }

  /// The name to show for this contact, or `nil` if the contact has no usable name.
  public func displayName(preferNickname: Bool) -> String? {
    if preferNickname, let nickname {
      return nickname
    }
    return fullName ?? nickname
  }

  private static func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

/// A contact as listed in the contact picker.
public struct ContactSummary: Sendable, Hashable, Identifiable {
  public let identifier: String
  public let name: String
  public let nickname: String?
  public let thumbnailData: Data?
  /// Matrix user IDs this contact is already linked to.
  public let linkedUserIDs: [String]

  public var id: String { identifier }

  public init(
    identifier: String, name: String, nickname: String?, thumbnailData: Data?,
    linkedUserIDs: [String]
  ) {
    self.identifier = identifier
    self.name = name
    self.nickname = nickname
    self.thumbnailData = thumbnailData
    self.linkedUserIDs = linkedUserIDs
  }

  public func matches(_ query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    return name.localizedStandardContains(query)
      || nickname?.localizedStandardContains(query) == true
      || linkedUserIDs.contains { $0.localizedStandardContains(query) }
  }
}

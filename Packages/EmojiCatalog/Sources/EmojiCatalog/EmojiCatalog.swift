import Foundation

/// A static Unicode/CLDR catalog whose category, subgroup, and emoji arrays preserve display order.
public struct EmojiCatalog: Codable, Equatable, Sendable {
  public static let supportedSchemaVersion = 1

  public let schemaVersion: Int
  public let emojiVersion: String
  public let unicodeVersion: String
  public let cldrVersion: String
  public let locale: String
  public let sources: [Source]
  public let categories: [Category]

  public init(
    schemaVersion: Int, emojiVersion: String, unicodeVersion: String, cldrVersion: String,
    locale: String, sources: [Source], categories: [Category]
  ) {
    self.schemaVersion = schemaVersion
    self.emojiVersion = emojiVersion
    self.unicodeVersion = unicodeVersion
    self.cldrVersion = cldrVersion
    self.locale = locale
    self.sources = sources
    self.categories = categories
  }

  public struct Source: Codable, Equatable, Sendable {
    public let url: String
    public let sha256: String

    public init(url: String, sha256: String) {
      self.url = url
      self.sha256 = sha256
    }
  }

  public struct Category: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var subgroups: [Subgroup]

    public init(id: String, name: String, subgroups: [Subgroup]) {
      self.id = id
      self.name = name
      self.subgroups = subgroups
    }
  }

  public struct Subgroup: Codable, Equatable, Sendable {
    public let id: String
    public var emojis: [Emoji]

    public init(id: String, emojis: [Emoji]) {
      self.id = id
      self.emojis = emojis
    }
  }

  public struct Emoji: Codable, Equatable, Sendable {
    public let emoji: String
    public let name: String
    public let keywords: [String]
    /// The Unicode Emoji introduction version.
    public let version: String
    /// Alternate qualification forms for lookup.
    public let aliases: [String]

    public init(emoji: String, name: String, keywords: [String], version: String, aliases: [String])
    {
      self.emoji = emoji
      self.name = name
      self.keywords = keywords
      self.version = version
      self.aliases = aliases
    }
  }

  public enum LoadError: Error, Equatable {
    case missingBundledResource
    case unsupportedSchemaVersion(Int)
  }

  /// Decodes JSON and rejects unsupported schema versions, unlike direct `JSONDecoder` decoding.
  public static func decode(_ data: Data) throws -> EmojiCatalog {
    let catalog = try JSONDecoder().decode(EmojiCatalog.self, from: data)
    guard catalog.schemaVersion == supportedSchemaVersion else {
      throw LoadError.unsupportedSchemaVersion(catalog.schemaVersion)
    }
    return catalog
  }

  /// Synchronously loads the library's resource.
  public static func loadBundled() throws -> EmojiCatalog {
    guard
      let url = Bundle.module.url(
        forResource: "emoji-catalog", withExtension: "json", subdirectory: "Emoji"
      )
    else {
      throw LoadError.missingBundledResource
    }
    return try decode(Data(contentsOf: url))
  }
}

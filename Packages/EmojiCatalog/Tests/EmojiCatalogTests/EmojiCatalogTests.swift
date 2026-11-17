import EmojiCatalog
import Foundation
import Testing

struct EmojiCatalogTests {
  @Test func bundledCatalogCounts() throws {
    let catalog = try EmojiCatalog.loadBundled()
    let emojis = catalog.categories.flatMap(\.subgroups).flatMap(\.emojis)

    #expect(catalog.schemaVersion == EmojiCatalog.supportedSchemaVersion)
    #expect(catalog.locale == "en")
    #expect(catalog.categories.count == 9)
    #expect(emojis.count == 3963)
    #expect(emojis.reduce(0) { $0 + $1.aliases.count } == 1272)
  }

  @Test func bundledSequencesAndAliases() throws {
    let catalog = try EmojiCatalog.loadBundled()
    let emojis = catalog.categories.flatMap(\.subgroups).flatMap(\.emojis)
    let heart = try #require(emojis.first { $0.emoji == "❤️" })
    #expect(heart.name == "red heart")
    #expect(heart.aliases.contains("❤"))
    #expect(heart.keywords.contains("love"))
    #expect(heart.version == "0.6")
    #expect(emojis.contains { $0.emoji == "👩‍💻" && $0.name == "woman technologist" })
    #expect(emojis.contains { $0.emoji == "👍🏽" && $0.name == "thumbs up: medium skin tone" })
    #expect(emojis.contains { $0.emoji == "🇩🇰" && $0.name == "flag: Denmark" })
    let rainbowFlag = try #require(emojis.first { $0.emoji == "🏳️‍🌈" })
    #expect(rainbowFlag.aliases.contains("🏳‍🌈"))

    let components = Set(["🏻", "🏼", "🏽", "🏾", "🏿", "🦰", "🦱", "🦳", "🦲"])
    #expect(emojis.allSatisfy { !components.contains($0.emoji) })
    #expect(!catalog.categories.contains { $0.id == "component" })
  }

  @Test func rejectsUnsupportedSchema() throws {
    let data = try JSONEncoder().encode(tinyCatalog(schemaVersion: 2))
    #expect(throws: EmojiCatalog.LoadError.unsupportedSchemaVersion(2)) {
      try EmojiCatalog.decode(data)
    }
  }

  @Test func rejectsMalformedJSON() {
    #expect(throws: DecodingError.self) {
      try EmojiCatalog.decode(Data("{not JSON}".utf8))
    }
  }

  @Test func bundledCatalogRoundTrip() throws {
    let catalog = try EmojiCatalog.loadBundled()
    let data = try JSONEncoder().encode(catalog)
    #expect(try EmojiCatalog.decode(data) == catalog)
  }

  @Test func publicInitializersAndMutableCollections() throws {
    let catalog = tinyCatalog()
    #expect(catalog.schemaVersion == 1)
    #expect(catalog.emojiVersion == "18.0")
    #expect(catalog.unicodeVersion == "18.0.0")
    #expect(catalog.cldrVersion == "49.0.0")
    #expect(catalog.locale == "en")
    #expect(
      catalog.sources == [EmojiCatalog.Source(url: "https://example.com/emoji", sha256: "abc")])
    let category = try #require(catalog.categories.first)
    #expect(category.id == "smileys-emotion")
    #expect(category.name == "Smileys & Emotion")
    let subgroup = try #require(category.subgroups.first)
    #expect(subgroup.id == "emotion")
    #expect(
      subgroup.emojis == [
        EmojiCatalog.Emoji(
          emoji: "❤️", name: "red heart", keywords: ["love"], version: "0.6", aliases: ["❤"])
      ])
    #expect(try EmojiCatalog.decode(JSONEncoder().encode(catalog)) == catalog)

    var mutableSubgroup = subgroup
    mutableSubgroup.emojis.append(subgroup.emojis[0])
    var mutableCategory = category
    mutableCategory.subgroups.append(mutableSubgroup)
    #expect(mutableCategory.subgroups.count == 2)
    #expect(mutableCategory.subgroups[1].emojis.count == 2)
  }

  private func tinyCatalog(schemaVersion: Int = 1) -> EmojiCatalog {
    EmojiCatalog(
      schemaVersion: schemaVersion, emojiVersion: "18.0", unicodeVersion: "18.0.0",
      cldrVersion: "49.0.0", locale: "en",
      sources: [.init(url: "https://example.com/emoji", sha256: "abc")],
      categories: [
        .init(
          id: "smileys-emotion", name: "Smileys & Emotion",
          subgroups: [
            .init(
              id: "emotion",
              emojis: [
                .init(
                  emoji: "❤️", name: "red heart", keywords: ["love"], version: "0.6",
                  aliases: ["❤"])
              ])
          ])
      ])
  }
}

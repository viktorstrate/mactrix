import EmojiCatalog
import Testing

@testable import MactrixApp

struct ReactionPickerModelTests {
  @Test func preservesCategoryAndSubgroupOrder() {
    let model = fixtureModel()
    #expect(model.categories.map(\.id) == [.category("smileys-emotion"), .category("people-body")])
    #expect(model.categories.map(\.title) == ["Smileys & Emotion", "People & Body"])
    #expect(model.categories[0].items.map(\.key) == ["😀", "❤️", "💙"])
    #expect(model.categories[1].items.map(\.key) == ["👍", "👩‍💻", "👨‍💻", "🧑‍🤝‍🧑"])
    #expect(model.sections(recentKeys: [], recentLimit: 21) == model.categories)
  }

  @Test func removesOnlySkinToneVariantsFromBrowsingAndCatalogSearch() {
    let model = fixtureModel()
    let keys = model.categories.flatMap(\.items).map(\.key)
    #expect(!keys.contains("👍🏽"))
    #expect(!keys.contains("🧑🏻‍🤝‍🧑🏿"))
    #expect(keys.contains("👩‍💻"))
    #expect(keys.contains("👨‍💻"))
    #expect(keys.contains("🧑‍🤝‍🧑"))
    #expect(model.search("thumbs").map(\.key) == ["👍"])
    #expect(model.search("dark skin").isEmpty)
    #expect(model.search("👍🏽").isEmpty)
    // Toned metadata is still indexed for use by Recents.
    #expect(model.item(for: "👍🏽").name == "thumbs up: medium skin tone")
  }

  @Test func recentsDeduplicateBeforeApplyingLimitAndPreserveFirstExactKey() {
    let model = fixtureModel()
    let items = model.recentItems(for: ["❤", "❤️", "❤", "👍🏽", "👍", "😀"], limit: 3)
    #expect(items.map(\.key) == ["❤", "👍🏽", "👍"])
    #expect(items.map(\.id) == ["❤", "👍🏽", "👍"])
    #expect(items.map(\.canonicalKey) == ["❤️", "👍🏽", "👍"])
    #expect(items[0].name == "red heart")
    #expect(items[0].keywords == ["love", "heart"])
  }

  @Test func nonpositiveRecentLimitsAndEmptyKeysDoNotCreateSection() {
    let model = fixtureModel()
    #expect(model.recentItems(for: ["😀"], limit: 0).isEmpty)
    #expect(model.recentItems(for: ["😀"], limit: -1).isEmpty)
    #expect(model.sections(recentKeys: ["😀"], recentLimit: 0) == model.categories)
    #expect(model.sections(recentKeys: ["", ""], recentLimit: 3) == model.categories)
    #expect(model.recentItems(for: ["", "😀", ""], limit: 1).map(\.key) == ["😀"])
  }

  @Test func recentsAreFirstWithoutRemovingItemsFromCategories() throws {
    let model = fixtureModel()
    let sections = model.sections(recentKeys: ["❤", "👍🏽"], recentLimit: 21)
    let recent = try #require(sections.first)
    #expect(recent.id == .recent)
    #expect(recent.title == "Recently Used")
    #expect(recent.systemSymbolName == "clock")
    #expect(recent.items.map(\.key) == ["❤", "👍🏽"])
    #expect(Array(sections.dropFirst()) == model.categories)
    #expect(sections[1].items.contains { $0.key == "❤️" })
  }

  @Test func metadataLookupPreservesCanonicalAndAlternateKeys() {
    let model = fixtureModel()
    let canonical = model.item(for: "❤️")
    let alternate = model.item(for: "❤")
    #expect(canonical.key == "❤️")
    #expect(alternate.key == "❤")
    #expect(canonical.metadata == alternate.metadata)
    #expect(canonical.canonicalKey == alternate.canonicalKey)
  }

  @Test func unknownRecentKeysHaveSearchableFallbackMetadata() throws {
    let model = fixtureModel()
    let unknown = "custom-reaction"
    let items = model.recentItems(for: [unknown, unknown, "🫨"], limit: 3)
    #expect(items.map(\.key) == [unknown, "🫨"])
    let first = try #require(items.first)
    #expect(first.metadata == nil)
    #expect(first.name == unknown)
    #expect(first.keywords.isEmpty)
    #expect(first.canonicalKey == unknown)
    #expect(model.search("CUSTOM", recentKeys: [unknown]).map(\.key) == [unknown])
    #expect(model.search("🫨", recentKeys: ["🫨"]).map(\.key) == ["🫨"])
  }

  @Test func searchesEnglishNamesKeywordsAndMultipleTerms() {
    let model = fixtureModel()
    #expect(model.search("grinning").map(\.key) == ["😀"])
    #expect(model.search("happy").map(\.key) == ["😀"])
    #expect(model.search("love").map(\.key) == ["❤️", "💙"])
    #expect(model.search("woman computer").map(\.key) == ["👩‍💻"])
    #expect(model.search("computer woman").map(\.key) == ["👩‍💻"])
    #expect(model.search("blue grinning").isEmpty)
  }

  @Test func searchIgnoresCaseDiacriticsAndExtraWhitespace() {
    let model = fixtureModel()
    #expect(model.search("  RÉD\n HEART \t").map(\.key) == ["❤️"])
    #expect(model.search("CAFE").map(\.key) == ["😀"])
  }

  @Test func emptyQueriesAndNoMatchesReturnNoResults() {
    let model = fixtureModel()
    for query in ["", " \n\t", "not-an-emoji", ":thumbsup:"] {
      #expect(model.search(query, recentKeys: ["👍"]).isEmpty)
    }
  }

  @Test func pastedEmojiAndQualificationAliasesResolveToCatalogEntries() {
    let model = fixtureModel()
    #expect(model.search("❤️").map(\.key) == ["❤️"])
    #expect(model.search("❤").map(\.key) == ["❤️"])
    #expect(model.search(" 👩‍💻 ").map(\.key) == ["👩‍💻"])
  }

  @Test func matchingRecentsRankFirstAndDeduplicateCatalogEquivalents() {
    let model = fixtureModel()
    let recents = ["💙", "😀", "❤", "❤️"]
    #expect(model.search("love", recentKeys: recents).map(\.key) == ["💙", "❤"])
    #expect(model.search("❤", recentKeys: recents).map(\.key) == ["❤"])
    #expect(model.search("❤️", recentKeys: recents).map(\.key) == ["❤"])
    #expect(model.search("love", recentKeys: recents, recentLimit: 1).map(\.key) == ["💙", "❤️"])
    #expect(model.search("love", recentKeys: recents, recentLimit: 0).map(\.key) == ["❤️", "💙"])
  }

  @Test func recentLimitAppliesBeforeSearchNotToMatchingItemsOnly() {
    let model = fixtureModel()
    #expect(
      model.search("thumbs", recentKeys: ["😀", "👍🏽"], recentLimit: 1).map(\.key) == ["👍"])
  }

  @Test func tonedRecentsRemainSearchableWithoutExposingOtherVariants() {
    let model = fixtureModel()
    #expect(model.search("thumbs", recentKeys: ["👍🏽"]).map(\.key) == ["👍🏽", "👍"])
    #expect(model.search("👍🏽", recentKeys: ["👍🏽"]).map(\.key) == ["👍🏽"])
    #expect(model.search("medium skin", recentKeys: ["👍🏽"]).map(\.key) == ["👍🏽"])
  }

  @Test func emptyCatalogSupportsRecentFallbacks() {
    let model = ReactionPickerModel(catalog: catalog(categories: []))
    #expect(model.categories.isEmpty)
    #expect(model.sections(recentKeys: [], recentLimit: 3).isEmpty)
    #expect(model.sections(recentKeys: ["❤️"], recentLimit: 3).map(\.id) == [.recent])
    #expect(model.search("❤️", recentKeys: ["❤️"]).map(\.key) == ["❤️"])
  }

  @Test func bundledCatalogHasStableCategoriesAndCompleteIconMapping() throws {
    let model = try ReactionPickerModel.loadBundled()
    let expectedIDs = [
      "smileys-emotion", "people-body", "animals-nature", "food-drink", "travel-places",
      "activities", "objects", "symbols", "flags",
    ]
    #expect(model.categories.map(\.id) == expectedIDs.map { .category($0) })
    #expect(Set(ReactionPickerModel.categorySystemSymbols.keys) == Set(expectedIDs))
    #expect(model.categories.allSatisfy { $0.systemSymbolName != nil && !$0.items.isEmpty })
    let items = model.categories.flatMap(\.items)
    #expect(
      items.allSatisfy { item in
        !item.key.unicodeScalars.contains { $0.properties.isEmojiModifier }
      })
    #expect(items.contains { $0.key == "👩‍💻" })
    #expect(model.search("love").contains { $0.key == "❤️" })
    #expect(model.item(for: "❤").canonicalKey == "❤️")
    // A second opening uses the same bundled data and preserves presentation order.
    #expect(try ReactionPickerModel.loadBundled().categories == model.categories)
  }

  private func fixtureModel() -> ReactionPickerModel {
    ReactionPickerModel(
      catalog: catalog(categories: [
        .init(
          id: "smileys-emotion", name: "Smileys & Emotion",
          subgroups: [
            .init(
              id: "face-smiling",
              emojis: [
                emoji("😀", "grinning face", keywords: ["happy", "café"])
              ]),
            .init(
              id: "emotion",
              emojis: [
                emoji("❤️", "red heart", keywords: ["love", "heart"], aliases: ["❤"]),
                emoji("💙", "blue heart", keywords: ["love", "heart"]),
              ]),
          ]),
        .init(
          id: "people-body", name: "People & Body",
          subgroups: [
            .init(
              id: "hand-fingers-closed",
              emojis: [
                emoji("👍", "thumbs up", keywords: ["approve"]),
                emoji(
                  "👍🏽", "thumbs up: medium skin tone", keywords: ["approve", "medium skin tone"]),
              ]),
            .init(
              id: "person-role",
              emojis: [
                emoji("👩‍💻", "woman technologist", keywords: ["computer"]),
                emoji("👨‍💻", "man technologist", keywords: ["computer"]),
              ]),
            .init(
              id: "family",
              emojis: [
                emoji("🧑‍🤝‍🧑", "people holding hands", keywords: ["couple"]),
                emoji(
                  "🧑🏻‍🤝‍🧑🏿", "people holding hands: light skin tone, dark skin tone", keywords: ["couple"]
                ),
              ]),
          ]),
      ]))
  }

  private func emoji(
    _ key: String, _ name: String, keywords: [String] = [], aliases: [String] = []
  ) -> EmojiCatalog.Emoji {
    .init(emoji: key, name: name, keywords: keywords, version: "0.6", aliases: aliases)
  }

  private func catalog(categories: [EmojiCatalog.Category]) -> EmojiCatalog {
    .init(
      schemaVersion: EmojiCatalog.supportedSchemaVersion, emojiVersion: "18.0",
      unicodeVersion: "18.0.0", cldrVersion: "49.0.0", locale: "en", sources: [],
      categories: categories)
  }
}

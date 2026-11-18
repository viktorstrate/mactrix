import EmojiCatalog
import Foundation

struct ReactionPickerModel: Sendable {
  struct Item: Equatable, Identifiable, Sendable {
    /// The exact Matrix reaction key.
    let key: String
    let metadata: EmojiCatalog.Emoji?

    var id: String { key }
    var name: String { metadata?.name ?? key }
    var keywords: [String] { metadata?.keywords ?? [] }
    var canonicalKey: String { metadata?.emoji ?? key }
  }

  struct Section: Equatable, Identifiable, Sendable {
    enum ID: Hashable, Sendable {
      case recent
      case category(String)
    }

    let id: ID
    let title: String
    let items: [Item]

    var systemSymbolName: String? {
      switch id {
      case .recent: "clock"
      case .category(let id): ReactionPickerModel.categorySystemSymbols[id]
      }
    }
  }

  static let categorySystemSymbols: [String: String] = [
    "smileys-emotion": "face.smiling",
    "people-body": "hand.wave",
    "animals-nature": "leaf",
    "food-drink": "fork.knife",
    "travel-places": "car",
    "activities": "soccerball",
    "objects": "lightbulb",
    "symbols": "heart",
    "flags": "flag",
  ]

  let categories: [Section]

  private struct SearchEntry: Sendable {
    let item: Item
    let text: String
  }

  private let metadataByKey: [String: EmojiCatalog.Emoji]
  private let searchEntries: [SearchEntry]

  // Static initialization is lazy and synchronized; subsequent openings reuse both the
  // decoded catalog and its indexes. Callers can load off the main actor on first use.
  private static let bundled = Result { try ReactionPickerModel(catalog: .loadBundled()) }

  static func loadBundled() throws -> ReactionPickerModel {
    try bundled.get()
  }

  init(catalog: EmojiCatalog) {
    var metadataByKey: [String: EmojiCatalog.Emoji] = [:]
    var searchEntries: [SearchEntry] = []
    var categories: [Section] = []

    for category in catalog.categories {
      var items: [Item] = []
      for emoji in category.subgroups.flatMap(\.emojis) {
        metadataByKey[emoji.emoji] = emoji
        for alias in emoji.aliases {
          metadataByKey[alias] = emoji
        }

        // Keep all entries in the lookup index so toned Recents still get metadata.
        // Do not infer variants by stripping modifiers: joined sequences can contain
        // multiple people, and gender/profession sequences are separate choices.
        guard !emoji.emoji.unicodeScalars.contains(where: { $0.properties.isEmojiModifier })
        else { continue }
        let item = Item(key: emoji.emoji, metadata: emoji)
        items.append(item)
        searchEntries.append(SearchEntry(item: item, text: Self.searchText(for: item)))
      }
      categories.append(
        Section(
          id: .category(category.id), title: Self.title(for: category), items: items))
    }

    self.metadataByKey = metadataByKey
    self.searchEntries = searchEntries
    self.categories = categories
  }

  /// The catalog only has English category names, so the known Unicode groups are translated here.
  private static func title(for category: EmojiCatalog.Category) -> String {
    switch category.id {
    case "smileys-emotion": String(localized: "Smileys & Emotion")
    case "people-body": String(localized: "People & Body")
    case "animals-nature": String(localized: "Animals & Nature")
    case "food-drink": String(localized: "Food & Drink")
    case "travel-places": String(localized: "Travel & Places")
    case "activities": String(localized: "Activities")
    case "objects": String(localized: "Objects")
    case "symbols": String(localized: "Symbols")
    case "flags": String(localized: "Flags")
    default: category.name
    }
  }

  func item(for key: String) -> Item {
    Item(key: key, metadata: metadataByKey[key])
  }

  /// Keeps the first exact key for each catalog equivalent, in SDK order.
  func recentItems(for keys: [String], limit: Int) -> [Item] {
    guard limit > 0 else { return [] }
    var seen = Set<String>()
    var items: [Item] = []
    for key in keys where !key.isEmpty {
      let item = item(for: key)
      guard seen.insert(item.canonicalKey).inserted else { continue }
      items.append(item)
      if items.count == limit { break }
    }
    return items
  }

  func sections(recentKeys: [String], recentLimit: Int) -> [Section] {
    let recents = recentItems(for: recentKeys, limit: recentLimit)
    guard !recents.isEmpty else { return categories }
    return [Section(id: .recent, title: String(localized: "Recently Used"), items: recents)]
      + categories
  }

  /// Empty/whitespace queries return no search results; use `sections` for browsing.
  /// Recent matches precede catalog matches, retaining their exact reaction keys.
  func search(
    _ query: String, recentKeys: [String] = [], recentLimit: Int = .max
  ) -> [Item] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let terms = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return [] }
    let emojiKey = metadataByKey[query]?.emoji
    var seen = Set<String>()
    var results: [Item] = []

    func appendIfMatching(_ item: Item, text: String) {
      let matches =
        item.key == query
        || (emojiKey != nil && item.canonicalKey == emojiKey)
        || terms.allSatisfy { text.contains($0) }
      guard matches, seen.insert(item.canonicalKey).inserted else { return }
      results.append(item)
    }

    for item in recentItems(for: recentKeys, limit: recentLimit) {
      appendIfMatching(item, text: Self.searchText(for: item))
    }
    for entry in searchEntries {
      appendIfMatching(entry.item, text: entry.text)
    }
    return results
  }

  private static func searchText(for item: Item) -> String {
    fold(([item.name] + item.keywords).joined(separator: "\n"))
  }

  private static func fold(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
  }
}

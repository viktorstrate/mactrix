import EmojiCatalog
import Foundation
import Testing

@testable import EmojiCatalogGenerator

struct EmojiCatalogGeneratorTests {
  private static let fixture = """
    # Version: 18.0
    # group: Smileys & Emotion
    # subgroup: emotion
    2764 FE0F ; fully-qualified # ❤️ E0.6 red heart
    2764 ; unqualified # ❤ E0.6 red heart
    # group: People & Body
    # subgroup: person-role
    1F469 1F3FD 200D 1F4BB ; fully-qualified # 👩🏽‍💻 E4.0 woman technologist: medium skin tone
    # group: Component
    # subgroup: skin-tone
    1F3FD ; component # 🏽 E1.0 medium skin tone
    """

  private static let baseAnnotations = Data(
    #"{"annotations":{"identity":{"language":"en"},"annotations":{"❤":{"default":["love","heart","heart"],"tts":["red heart"]}}}}"#
      .utf8)
  private static let derivedAnnotations = Data(
    #"{"annotationsDerived":{"identity":{"language":"en"},"annotations":{"👩🏽‍💻":{"default":["developer","woman"],"tts":["woman technologist: medium skin tone"]}}}}"#
      .utf8)

  @Test func preservesCategoryOrderAndSequences() throws {
    let categories = try makeFixtureCategories()
    #expect(categories.map(\.id) == ["smileys-emotion", "people-body"])
    #expect(categories.flatMap(\.subgroups).map(\.id) == ["emotion", "person-role"])
    let entries = categories.flatMap(\.subgroups).flatMap(\.emojis)
    #expect(entries.map(\.emoji) == ["❤️", "👩🏽‍💻"])
    #expect(entries[0].aliases == ["❤"])
    #expect(entries[0].keywords == ["heart", "love"])
    #expect(entries[1].name == "woman technologist: medium skin tone")
    #expect(entries[1].version == "4.0")
  }

  @Test func generatedCategoriesRoundTrip() throws {
    let categories = try makeFixtureCategories()
    let data = try JSONEncoder().encode(categories)
    #expect(try JSONDecoder().decode([EmojiCatalog.Category].self, from: data) == categories)
  }

  @Test(arguments: [
    ("❤️", "❤"), ("❤︎", "❤"), ("👁️‍🗨️", "👁‍🗨"), ("👩🏽‍💻", "👩🏽‍💻"), ("🇩🇰", "🇩🇰"),
  ])
  func annotationLookupKey(input: String, expected: String) {
    #expect(annotationKey(input) == expected)
  }

  @Test func permitsPartialNonEmojiAnnotations() throws {
    let data = Data(
      #"{"annotations":{"identity":{"language":"en"},"annotations":{"₴":{"tts":["hryvnia"]},"$":{"default":["dollar"]}}}}"#
        .utf8)
    let annotations = try parseAnnotations(data, derived: false, locale: "en")
    #expect(annotations["₴"]?.keywords == [])
    #expect(annotations["₴"]?.names == ["hryvnia"])
    #expect(annotations["$"]?.names == [])
    #expect(annotations["$"]?.keywords == ["dollar"])
  }

  @Test(arguments: ["version", "group", "scalar", "duplicate"])
  func rejectsInvalidEmojiData(problem: String) {
    let text: String
    switch problem {
    case "version":
      text = Self.fixture.replacingOccurrences(of: "# Version: 18.0", with: "# Version: 17.0")
    case "group":
      text = Self.fixture.replacingOccurrences(of: "People & Body", with: "Unknown")
    case "scalar":
      text = Self.fixture.replacingOccurrences(of: "2764 FE0F", with: "110000")
    default:
      text = Self.fixture + "\n1F3FD ; component # 🏽 E1.0 medium skin tone"
    }
    #expect(throws: GenerationError.self) {
      try parseEmojiTest(text, expectedVersion: "18.0")
    }
  }

  @Test(arguments: ["missing", "keywords", "name", "inherited"])
  func rejectsIncompleteEmojiAnnotations(problem: String) throws {
    let records = try parseEmojiTest(Self.fixture, expectedVersion: "18.0")
    var annotations = try fixtureAnnotations()
    switch problem {
    case "missing":
      annotations.removeValue(forKey: "❤")
    case "keywords":
      annotations["❤"] = Annotation(keywords: [], names: ["red heart"])
    case "name":
      annotations["❤"] = Annotation(keywords: ["love"], names: [])
    default:
      annotations["❤"] = Annotation(keywords: ["↑↑↑"], names: ["red heart"])
    }
    #expect(throws: GenerationError.self) {
      try makeCategories(records: records, annotations: annotations)
    }
  }

  @Test func rejectsConflictingAnnotationKeys() {
    #expect(throws: GenerationError.self) {
      try mergeAnnotations([
        ["❤": Annotation(keywords: ["love"], names: ["heart"])],
        ["❤️": Annotation(keywords: ["different"], names: ["heart"])],
      ])
    }
  }

  @Test func rejectsOrphanAlternateForm() throws {
    let records = try parseEmojiTest(Self.fixture, expectedVersion: "18.0")
      .filter { $0.emoji != "❤️" }
    let annotations = try fixtureAnnotations()
    #expect(throws: GenerationError.self) {
      try makeCategories(records: records, annotations: annotations)
    }
  }

  @Test func rejectsWrongAnnotationEnvelope() {
    #expect(throws: GenerationError.self) {
      try parseAnnotations(Self.baseAnnotations, derived: true, locale: "en")
    }
  }

  @Test func rejectsWrongAnnotationLocale() {
    #expect(throws: GenerationError.self) {
      try parseAnnotations(Self.baseAnnotations, derived: false, locale: "fr")
    }
  }

  private func fixtureAnnotations() throws -> [String: Annotation] {
    try mergeAnnotations([
      parseAnnotations(Self.baseAnnotations, derived: false, locale: "en"),
      parseAnnotations(Self.derivedAnnotations, derived: true, locale: "en"),
    ])
  }

  private func makeFixtureCategories() throws -> [EmojiCatalog.Category] {
    try makeCategories(
      records: parseEmojiTest(Self.fixture, expectedVersion: "18.0"),
      annotations: fixtureAnnotations())
  }
}

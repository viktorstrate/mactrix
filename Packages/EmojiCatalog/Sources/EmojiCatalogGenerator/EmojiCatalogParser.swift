import EmojiCatalog
import Foundation

struct GenerationError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

typealias Category = EmojiCatalog.Category
typealias Subgroup = EmojiCatalog.Subgroup
typealias Emoji = EmojiCatalog.Emoji

struct Record {
  let emoji: String
  let status: String
  let version: String
  let group: String
  let subgroup: String
}

struct Annotation: Decodable, Equatable {
  let keywords: [String]
  let names: [String]

  enum CodingKeys: String, CodingKey {
    case keywords = "default"
    case names = "tts"
  }
}

extension Annotation {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // CLDR also annotates non-emoji symbols, some with only a name or only keywords.
    keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    names = try container.decodeIfPresent([String].self, forKey: .names) ?? []
  }
}

private struct AnnotationDocument: Decodable {
  struct Contents: Decodable {
    struct Identity: Decodable {
      let language: String
    }

    let identity: Identity
    let annotations: [String: Annotation]
  }

  let annotations: Contents?
  let annotationsDerived: Contents?
}

let categoryIDs = [
  "Smileys & Emotion": "smileys-emotion",
  "People & Body": "people-body",
  "Animals & Nature": "animals-nature",
  "Food & Drink": "food-drink",
  "Travel & Places": "travel-places",
  "Activities": "activities",
  "Objects": "objects",
  "Symbols": "symbols",
  "Flags": "flags",
]

// CLDR annotation keys omit presentation selectors, including those inside ZWJ sequences.
// This is a metadata lookup key, not a replacement for an emoji.
func annotationKey(_ string: String) -> String {
  String(
    String.UnicodeScalarView(
      string.unicodeScalars.filter {
        $0.value != 0xFE0E && $0.value != 0xFE0F
      }))
}

func parseEmojiTest(_ text: String, expectedVersion: String) throws -> [Record] {
  guard text.components(separatedBy: .newlines).contains("# Version: \(expectedVersion)") else {
    throw GenerationError("emoji-test.txt does not declare expected version \(expectedVersion).")
  }

  let descriptionPattern = try NSRegularExpression(pattern: #"^\S+\s+E([0-9]+\.[0-9]+)\s+.+$"#)
  let validStatuses: Set<String> = [
    "fully-qualified", "minimally-qualified", "unqualified", "component",
  ]
  var group: String?
  var subgroup: String?
  var seenGroups = Set<String>()
  var seenSubgroups = Set<String>()
  var seenSequences = Set<String>()
  var records: [Record] = []

  for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    let location = "emoji-test.txt:\(offset + 1)"
    if line.hasPrefix("# group: ") {
      let name = String(line.dropFirst("# group: ".count))
      guard categoryIDs[name] != nil || name == "Component" else {
        throw GenerationError("\(location): Unknown group '\(name)'; update categoryIDs.")
      }
      guard seenGroups.insert(name).inserted else {
        throw GenerationError("\(location): Repeated group '\(name)'.")
      }
      group = name
      subgroup = nil
      continue
    }
    if line.hasPrefix("# subgroup: ") {
      let name = String(line.dropFirst("# subgroup: ".count))
      guard let group, !name.isEmpty,
        seenSubgroups.insert("\(group)/\(name)").inserted
      else {
        throw GenerationError("\(location): Invalid or repeated subgroup.")
      }
      subgroup = name
      continue
    }
    if line.isEmpty || line.hasPrefix("#") { continue }

    guard let group, let subgroup,
      let semicolon = line.firstIndex(of: ";"),
      let comment = line[semicolon...].firstIndex(of: "#")
    else {
      throw GenerationError(
        "\(location): Expected code points; status # description in a subgroup.")
    }
    let status = line[line.index(after: semicolon)..<comment]
      .trimmingCharacters(in: .whitespaces)
    guard validStatuses.contains(status) else {
      throw GenerationError("\(location): Unknown qualification status '\(status)'.")
    }
    let points = line[..<semicolon].split(whereSeparator: { $0.isWhitespace })
    var scalars = String.UnicodeScalarView()
    for point in points {
      guard let value = UInt32(point, radix: 16), let scalar = Unicode.Scalar(value) else {
        throw GenerationError("\(location): Invalid Unicode scalar '\(point)'.")
      }
      scalars.append(scalar)
    }
    guard !scalars.isEmpty else {
      throw GenerationError("\(location): Empty emoji sequence.")
    }
    let emoji = String(scalars)
    guard seenSequences.insert(emoji).inserted else {
      throw GenerationError("\(location): Duplicate sequence '\(emoji)'.")
    }
    let description = line[line.index(after: comment)...]
      .trimmingCharacters(in: .whitespaces)
    guard
      let match = descriptionPattern.firstMatch(
        in: description, range: NSRange(description.startIndex..., in: description)),
      let versionRange = Range(match.range(at: 1), in: description)
    else {
      throw GenerationError("\(location): Expected an emoji, E<version>, and name in the comment.")
    }
    guard (status == "component") == (group == "Component") else {
      throw GenerationError("\(location): Component status/group mismatch.")
    }
    records.append(
      Record(
        emoji: emoji, status: status, version: String(description[versionRange]),
        group: group, subgroup: subgroup))
  }
  guard records.contains(where: { $0.status == "fully-qualified" }) else {
    throw GenerationError("emoji-test.txt contains no fully qualified emojis.")
  }
  return records
}

func parseAnnotations(_ data: Data, derived: Bool, locale: String) throws -> [String: Annotation] {
  let document = try JSONDecoder().decode(AnnotationDocument.self, from: data)
  let contents = derived ? document.annotationsDerived : document.annotations
  guard let contents, contents.identity.language == locale else {
    throw GenerationError(
      "Expected \(locale) \(derived ? "derived" : "base") annotations.")
  }
  return contents.annotations
}

func mergeAnnotations(_ documents: [[String: Annotation]]) throws -> [String: Annotation] {
  var result: [String: Annotation] = [:]
  for document in documents {
    for (emoji, annotation) in document.sorted(by: { $0.key < $1.key }) {
      let key = annotationKey(emoji)
      if let previous = result[key], previous != annotation {
        throw GenerationError("Conflicting CLDR annotations for '\(emoji)'.")
      }
      result[key] = annotation
    }
  }
  return result
}

func makeCategories(
  records: [Record], annotations: [String: Annotation]
) throws -> [Category] {
  let qualified = records.filter { $0.status == "fully-qualified" }
  var canonicalKeys = Set<String>()
  for record in qualified {
    guard canonicalKeys.insert(annotationKey(record.emoji)).inserted else {
      throw GenerationError("Ambiguous fully qualified emoji '\(record.emoji)'.")
    }
  }
  var aliases: [String: [String]] = [:]
  for record in records
  where record.status == "minimally-qualified" || record.status == "unqualified" {
    let key = annotationKey(record.emoji)
    guard canonicalKeys.contains(key) else {
      throw GenerationError("Alternate form '\(record.emoji)' has no fully qualified entry.")
    }
    aliases[key, default: []].append(record.emoji)
  }

  var categories: [Category] = []
  for record in qualified {
    let key = annotationKey(record.emoji)
    guard let annotation = annotations[key], annotation.names.count == 1,
      let name = annotation.names.first,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !annotation.keywords.isEmpty,
      annotation.keywords.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      ),
      !annotation.names.contains("↑↑↑"), !annotation.keywords.contains("↑↑↑")
    else {
      throw GenerationError("Missing or invalid CLDR name/keywords for '\(record.emoji)'.")
    }
    guard let categoryID = categoryIDs[record.group] else {
      throw GenerationError("No category ID for '\(record.group)'.")
    }
    if categories.last?.id != categoryID {
      categories.append(Category(id: categoryID, name: record.group, subgroups: []))
    }
    let categoryIndex = categories.count - 1
    if categories[categoryIndex].subgroups.last?.id != record.subgroup {
      categories[categoryIndex].subgroups.append(Subgroup(id: record.subgroup, emojis: []))
    }
    let subgroupIndex = categories[categoryIndex].subgroups.count - 1
    categories[categoryIndex].subgroups[subgroupIndex].emojis.append(
      Emoji(
        emoji: record.emoji, name: name,
        keywords: Array(Set(annotation.keywords)).sorted(), version: record.version,
        aliases: aliases[key, default: []]))
  }
  return categories
}

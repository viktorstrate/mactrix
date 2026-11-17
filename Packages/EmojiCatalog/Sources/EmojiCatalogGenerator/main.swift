import CryptoKit
import Darwin
import EmojiCatalog
import Foundation

private let emojiVersion = "18.0"
private let unicodeVersion = "18.0.0"
private let cldrVersion = "49.0.0"
private let annotationLocale = "en"

private let emojiURL = URL(
  string: "https://www.unicode.org/Public/\(unicodeVersion)/emoji/emoji-test.txt")!
private let cldrBaseURL =
  "https://raw.githubusercontent.com/unicode-org/cldr-json/\(cldrVersion)"
private let annotationsURL = URL(
  string:
    "\(cldrBaseURL)/cldr-json/cldr-annotations-full/annotations/\(annotationLocale)/annotations.json"
)!
private let derivedAnnotationsURL = URL(
  string:
    "\(cldrBaseURL)/cldr-json/cldr-annotations-derived-full/annotationsDerived/\(annotationLocale)/annotations.json"
)!
private let licenseURL = URL(string: "\(cldrBaseURL)/LICENSE")!

private func download(_ url: URL) async throws -> Data {
  print("Downloading \(url.absoluteString)")
  var request = URLRequest(url: url)
  request.timeoutInterval = 60
  do {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw GenerationError(
        "HTTP \((response as? HTTPURLResponse)?.statusCode.description ?? "unknown")")
    }
    guard !data.isEmpty else { throw GenerationError("Empty response") }
    return data
  } catch {
    throw GenerationError("Download failed for \(url.absoluteString): \(error)")
  }
}

private func utf8(_ data: Data, source: URL) throws -> String {
  guard let string = String(data: data, encoding: .utf8) else {
    throw GenerationError("Invalid UTF-8 from \(source.absoluteString).")
  }
  return string
}

private func generate(checkOnly: Bool) async throws {
  let emojiData = try await download(emojiURL)
  let annotationsData = try await download(annotationsURL)
  let derivedData = try await download(derivedAnnotationsURL)
  let licenseData = try await download(licenseURL)
  let emojiText = try utf8(emojiData, source: emojiURL)
  let licenseText = try utf8(licenseData, source: licenseURL)
  guard licenseText.hasPrefix("UNICODE LICENSE V3"),
    licenseText.contains("COPYRIGHT AND PERMISSION NOTICE")
  else {
    throw GenerationError("Unrecognized Unicode license; review before regenerating.")
  }
  let records = try parseEmojiTest(emojiText, expectedVersion: emojiVersion)
  let annotations = try mergeAnnotations([
    parseAnnotations(annotationsData, derived: false, locale: annotationLocale),
    parseAnnotations(derivedData, derived: true, locale: annotationLocale),
  ])
  let categories = try makeCategories(records: records, annotations: annotations)
  guard Set(categories.map(\.id)) == Set(categoryIDs.values) else {
    throw GenerationError("Catalog is missing expected categories.")
  }
  let inputs = [
    (emojiURL, emojiData), (annotationsURL, annotationsData),
    (derivedAnnotationsURL, derivedData), (licenseURL, licenseData),
  ]
  let sources = inputs.map { url, data in
    EmojiCatalog.Source(
      url: url.absoluteString,
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }
  let catalog = EmojiCatalog(
    schemaVersion: EmojiCatalog.supportedSchemaVersion, emojiVersion: emojiVersion,
    unicodeVersion: unicodeVersion,
    cldrVersion: cldrVersion, locale: annotationLocale, sources: sources, categories: categories)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  var catalogData = try encoder.encode(catalog)
  catalogData.append(0x0A)
  let notices = emojiText.components(separatedBy: .newlines)
    .filter { $0.hasPrefix("# ©") || $0.hasPrefix("# Unicode and the Unicode Logo") }
    .map { String($0.dropFirst(2)) }
  guard !notices.isEmpty else { throw GenerationError("Missing emoji copyright notice.") }
  let bundledLicense = Data(
    ("Emoji data (\(emojiURL.absoluteString)):\n" + notices.joined(separator: "\n")
      + "\n\nCLDR data and license (\(licenseURL.absoluteString)):\n" + licenseText).utf8)

  let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let directory = packageDirectory.appendingPathComponent(
    "Sources/EmojiCatalog/Resources/Emoji", isDirectory: true)
  let outputs = [("emoji-catalog.json", catalogData), ("UNICODE-LICENSE.txt", bundledLicense)]
  // Finish every download, parse, and validation before touching committed resources.
  if !checkOnly {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  for (name, data) in outputs {
    let destination = directory.appendingPathComponent(name)
    let existing = try? Data(contentsOf: destination)
    if existing == data {
      print("Unchanged: \(destination.path)")
    } else if checkOnly {
      throw GenerationError(
        "Missing or stale resource: \(destination.path). Run the generator without --check.")
    } else {
      try data.write(to: destination, options: .atomic)
      print("Wrote: \(destination.path)")
    }
  }
  let count = categories.flatMap(\.subgroups).flatMap(\.emojis).count
  let aliasCount = categories.flatMap(\.subgroups).flatMap(\.emojis).flatMap(\.aliases).count
  print(
    "Validated \(count) emojis, \(aliasCount) alternate forms, and \(categories.count) categories.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  switch arguments {
  case []:
    try await generate(checkOnly: false)
  case ["--check"]:
    try await generate(checkOnly: true)
  case ["--help"], ["-h"]:
    print(
      """
      Usage: swift run --package-path Packages/EmojiCatalog generate-emoji-catalog [--check | --help]

      No arguments: download pinned Unicode/CLDR data and regenerate bundled resources.
      --check:      download and validate, failing if committed resources differ; never writes.

      Output paths are relative to the generator's source file, not the working directory.
      Generation and --check require HTTPS network access.
      """)
  default:
    throw GenerationError("Unknown arguments. Use --help for usage.")
  }
} catch {
  FileHandle.standardError.write(Data("Emoji catalog generation failed: \(error)\n".utf8))
  exit(EXIT_FAILURE)
}

import Foundation

/// A Matrix user mention and the UTF-16 range of its entire link in the original Markdown.
public struct MarkdownMention: Equatable, Sendable {
  public let range: NSRange
  public let userID: String
  public let username: String
}

/// Finds inline user links in the format emitted by Mactrix's mention serializer.
///
/// This is not a Markdown renderer: unrelated source is left untouched, and labels are
/// unescaped without interpreting their formatting. Images, escaped links, and links inside
/// inline or fenced code are ignored. Reference links and link titles are not supported.
public func parseMarkdownMentions(_ markdown: String) -> [MarkdownMention] {
  MarkdownMentionScanner(markdown).parse()
}

private struct MarkdownMentionScanner {
  let markdown: String
  // Scalars keep ASCII syntax distinct from surrounding combining marks.
  var source: String.UnicodeScalarView { markdown.unicodeScalars }

  init(_ markdown: String) {
    self.markdown = markdown
  }

  func parse() -> [MarkdownMention] {
    var mentions: [MarkdownMention] = []
    var index = source.startIndex
    while index < source.endIndex {
      if index == source.startIndex || isNewline(source[source.index(before: index)]),
        let end = codeBlockEnd(at: index)
      {
        index = end
        continue
      }
      if source[index] == "\\", source.index(after: index) < source.endIndex,
        isPunctuation(source[source.index(after: index)])
      {
        index = source.index(index, offsetBy: 2)
        continue
      }
      if source[index] == "`" {
        let delimiterEnd = runEnd(at: index)
        index =
          inlineCodeEnd(
            after: delimiterEnd, length: source.distance(from: index, to: delimiterEnd))
          ?? delimiterEnd
        continue
      }
      if source[index] == "!", source.index(after: index) < source.endIndex,
        source[source.index(after: index)] == "[",
        let image = link(at: source.index(after: index))
      {
        index = image.end
        continue
      }
      if source[index] == "[", let link = link(at: index) {
        if let userID = Self.userID(from: link.destination) {
          mentions.append(
            MarkdownMention(
              range: NSRange(index..<link.end, in: markdown),
              userID: userID, username: link.username))
        }
        index = link.end
        continue
      }
      source.formIndex(after: &index)
    }
    return mentions
  }

  private func link(at start: String.Index)
    -> (end: String.Index, username: String, destination: String)?
  {
    var index = source.index(after: start)
    var depth = 1
    while index < source.endIndex {
      if source[index] == "\\", source.index(after: index) < source.endIndex,
        isPunctuation(source[source.index(after: index)])
      {
        index = source.index(index, offsetBy: 2)
        continue
      }
      if source[index] == "[" { depth += 1 }
      if source[index] == "]" {
        depth -= 1
        if depth == 0 { break }
      }
      source.formIndex(after: &index)
    }
    guard index < source.endIndex, source.index(after: index) < source.endIndex,
      source[source.index(after: index)] == "("
    else { return nil }
    let label = source.index(after: start)..<index
    index = source.index(index, offsetBy: 2)
    let destinationStart = index
    depth = 1
    while index < source.endIndex {
      // The serializer emits a single bare destination, without titles or whitespace.
      if source[index] == " " || source[index] == "\t" || isNewline(source[index]) { return nil }
      if source[index] == "\\", source.index(after: index) < source.endIndex,
        isPunctuation(source[source.index(after: index)])
      {
        index = source.index(index, offsetBy: 2)
        continue
      }
      if source[index] == "(" { depth += 1 }
      if source[index] == ")" {
        depth -= 1
        if depth == 0 {
          return (
            source.index(after: index), decodedLiteral(in: label),
            decodedLiteral(in: destinationStart..<index)
          )
        }
      }
      source.formIndex(after: &index)
    }
    return nil
  }

  private func codeBlockEnd(at start: String.Index) -> String.Index? {
    let opening = fenceStart(at: start)
    guard opening < source.endIndex, source[opening] == "`" || source[opening] == "~" else {
      return nil
    }
    let delimiterEnd = runEnd(at: opening)
    let length = source.distance(from: opening, to: delimiterEnd)
    guard length >= 3 else { return nil }
    let openingLineEnd = lineEnd(at: delimiterEnd)
    // A backtick fence's info string cannot contain backticks.
    if source[opening] == "`", source[delimiterEnd..<openingLineEnd].contains("`") { return nil }

    var index = nextLine(at: openingLineEnd)
    while index < source.endIndex {
      let closing = fenceStart(at: index)
      let endOfLine = lineEnd(at: index)
      if closing < source.endIndex, source[closing] == source[opening] {
        let closingEnd = runEnd(at: closing)
        if source.distance(from: closing, to: closingEnd) >= length,
          source[closingEnd..<endOfLine].allSatisfy({ $0 == " " || $0 == "\t" })
        {
          return nextLine(at: endOfLine)
        }
      }
      index = nextLine(at: endOfLine)
    }
    return source.endIndex
  }

  private func fenceStart(at start: String.Index) -> String.Index {
    var index = start
    while index < source.endIndex, source[index] == " ",
      source.distance(from: start, to: index) < 3
    {
      source.formIndex(after: &index)
    }
    return index
  }

  private func inlineCodeEnd(after start: String.Index, length: Int) -> String.Index? {
    var index = start
    while index < source.endIndex {
      if source[index] == "`" {
        let end = runEnd(at: index)
        if source.distance(from: index, to: end) == length { return end }
        index = end
      } else {
        source.formIndex(after: &index)
      }
    }
    return nil
  }

  private func runEnd(at start: String.Index) -> String.Index {
    var index = source.index(after: start)
    while index < source.endIndex, source[index] == source[start] {
      source.formIndex(after: &index)
    }
    return index
  }

  private func lineEnd(at start: String.Index) -> String.Index {
    var index = start
    while index < source.endIndex, !isNewline(source[index]) {
      source.formIndex(after: &index)
    }
    return index
  }

  private func nextLine(at end: String.Index) -> String.Index {
    guard end < source.endIndex else { return end }
    let next = source.index(after: end)
    if source[end] == "\r", next < source.endIndex, source[next] == "\n" {
      return source.index(after: next)
    }
    return next
  }

  private func isNewline(_ character: Unicode.Scalar) -> Bool {
    character == "\n" || character == "\r"
  }

  private func isPunctuation(_ character: Unicode.Scalar) -> Bool {
    ("!"..."/").contains(character) || (":"..."@").contains(character)
      || ("["..."`").contains(character) || ("{"..."~").contains(character)
  }

  private func decodedLiteral(in range: Range<String.Index>) -> String {
    var unescaped = String.UnicodeScalarView()
    var index = range.lowerBound
    while index < range.upperBound {
      if source[index] == "\\", source.index(after: index) < range.upperBound,
        isPunctuation(source[source.index(after: index)])
      {
        source.formIndex(after: &index)
      }
      unescaped.append(source[index])
      source.formIndex(after: &index)
    }
    // Decode only the serializer's entities, with ampersands last to avoid recursive decoding.
    return String(unescaped)
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func userID(from destination: String) -> String? {
    guard destination.removingPercentEncoding != nil,
      !destination.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      }),
      let components = URLComponents(string: destination),
      components.scheme == "https", components.host == "matrix.to",
      components.user == nil, components.password == nil, components.port == nil,
      components.path == "/", components.query == nil,
      let fragment = components.percentEncodedFragment?.removingPercentEncoding,
      fragment.hasPrefix("/@")
    else { return nil }

    let userID = String(fragment.dropFirst())
    guard let colon = userID.firstIndex(of: ":"),
      userID.distance(from: userID.startIndex, to: colon) > 1,
      !userID.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      })
    else { return nil }
    let localpart = userID[userID.index(after: userID.startIndex)..<colon]
    guard !localpart.contains(where: { "@?#\\".contains($0) }) else { return nil }
    let server = String(userID[userID.index(after: colon)...])
    // A slash is valid in a user localpart, but not in the server (e.g. an event permalink).
    guard server.wholeMatch(of: /(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(?::[0-9]+)?/) != nil,
      let serverComponents = URLComponents(string: "https://" + server),
      serverComponents.url != nil,
      let host = serverComponents.host, !host.isEmpty
    else { return nil }
    if let port = serverComponents.port, !(1...65535).contains(port) { return nil }
    return userID
  }
}

import Foundation
import MactrixUI
import MessageFormatting
import Testing

struct MarkdownMentionTests {
  @Test func emptyInputHasNoMentions() {
    #expect(parseMarkdownMentions("").isEmpty)
  }

  @Test func parsesSimpleMention() throws {
    let link = "[Alice](https://matrix.to/#/@alice:example.org)"

    try expectSingleMention(
      in: link, link: link, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: [
    "Alice",
    "Alice [work] (mobile)",
    "A & B <friends> \"quoted\" 'name'",
    "Literal &amp; &lt; &gt; &quot; &#39;",
    "🧑🏽‍💻 Zoë 東京 e\u{301}",
  ])
  func roundTripsDragPayloadLabels(username: String) throws {
    let payload = UserDragPayload(userId: "@alice:example.org", username: username)
    let link = try #require(payload.markdownLink)

    try expectSingleMention(
      in: link, link: link, userID: payload.userId, username: payload.username)
  }

  @Test(arguments: [
    "@alice:example.org",
    "@alice/mobile:example.org",
    "@alice:example.org:8448",
    "@alice:[2001:db8::1]",
    "@alice:[2001:db8::1]:8448",
    "@a&b:example.org",
    "@o'hara:example.org",
    "@alice%41:example.org",
  ])
  func roundTripsDragPayloadUserIDs(userID: String) throws {
    let payload = UserDragPayload(userId: userID, username: "Alice [mobile] & friends")
    let link = try #require(payload.markdownLink)

    try expectSingleMention(
      in: link, link: link, userID: payload.userId, username: payload.username)
  }

  @Test func decodesSupportedHTMLEntitiesInLabel() throws {
    let link =
      "[A &amp; B &lt;x&gt; &quot;q&quot; &#39;s&#39;](https://matrix.to/#/@alice:example.org)"

    try expectSingleMention(
      in: link, link: link, userID: "@alice:example.org", username: "A & B <x> \"q\" 's'")
  }

  @Test func decodesHTMLEntitiesOnlyOnce() throws {
    let link =
      "[&amp;lt; &amp;gt; &amp;quot; &amp;#39; &amp;amp;](https://matrix.to/#/@a&amp;amp;b:example.org)"

    try expectSingleMention(
      in: link, link: link, userID: "@a&amp;b:example.org",
      username: "&lt; &gt; &quot; &#39; &amp;")
  }

  @Test func unescapesMarkdownPunctuationInLabel() throws {
    let link = #"[Alice \[work\] \(mobile\)](https://matrix.to/#/@alice:example.org)"#

    try expectSingleMention(
      in: link, link: link, userID: "@alice:example.org", username: "Alice [work] (mobile)")
  }

  @Test func decodesPercentEncodedUserIDOnce() throws {
    let link = "[Alice](https://matrix.to/#/%40alice%252Fmobile%3Aexample.org)"

    try expectSingleMention(
      in: link, link: link, userID: "@alice%2Fmobile:example.org", username: "Alice")
  }

  @Test func acceptsPercentEncodedLocalpartSlash() throws {
    let link = "[Alice](https://matrix.to/#/%40alice%2Fmobile%3Aexample.org)"

    try expectSingleMention(
      in: link, link: link, userID: "@alice/mobile:example.org", username: "Alice")
  }

  @Test func reportsEntireOriginalLinksInUTF16Order() throws {
    let alice = UserDragPayload(userId: "@alice:example.org", username: "👩🏽‍💻 [Alice]")
    let bob = UserDragPayload(userId: "@bob:example.org", username: "東京 & Bob")
    let aliceLink = try #require(alice.markdownLink)
    let bobLink = try #require(bob.markdownLink)
    let prefix = "🧭 e\u{301} Hello "
    let separator = " — 🌍 then "
    let markdown = prefix + aliceLink + separator + bobLink + "!"

    let mentions = parseMarkdownMentions(markdown)

    #expect(mentions.count == 2)
    let first = try #require(mentions.first)
    let second = try #require(mentions.dropFirst().first)
    #expect(first.userID == alice.userId)
    #expect(first.username == alice.username)
    #expect(first.range == NSRange(location: prefix.utf16.count, length: aliceLink.utf16.count))
    #expect(second.userID == bob.userId)
    #expect(second.username == bob.username)
    #expect(
      second.range
        == NSRange(
          location: (prefix + aliceLink + separator).utf16.count, length: bobLink.utf16.count))
    #expect((markdown as NSString).substring(with: first.range) == aliceLink)
    #expect((markdown as NSString).substring(with: second.range) == bobLink)
  }

  @Test func preservesRepeatedAndAdjacentMentions() throws {
    let link = "[Alice](https://matrix.to/#/@alice:example.org)"
    let mentions = parseMarkdownMentions(link + link)

    #expect(mentions.count == 2)
    let first = try #require(mentions.first)
    let second = try #require(mentions.dropFirst().first)
    #expect(first.range == NSRange(location: 0, length: link.utf16.count))
    #expect(second.range == NSRange(location: link.utf16.count, length: link.utf16.count))
    #expect(first.userID == second.userID)
    #expect(first.username == second.username)
    #expect(first != second)
    #expect(mentions == parseMarkdownMentions(link + link))
  }

  @Test(arguments: [
    "https://example.org/#/@alice:example.org",
    "http://matrix.to/#/@alice:example.org",
    "https://matrix.to.evil.example/#/@alice:example.org",
    "https://evil-matrix.to/#/@alice:example.org",
    "https://alice@matrix.to/#/@alice:example.org",
    "https://alice:secret@matrix.to/#/@alice:example.org",
    "https://matrix.to:443/#/@alice:example.org",
    "https://matrix.to/other/#/@alice:example.org",
    "https://matrix.to// #/@alice:example.org",
    "https://matrix.to/?via=example.org#/@alice:example.org",
    "https://matrix.to/#/@alice:example.org?via=example.org",
    "https://matrix.to/#/@alice:example.org/$event:example.org",
    "https://matrix.to/#/!room:example.org",
    "https://matrix.to/#/#room:example.org",
    "https://matrix.to/#/!room:example.org/$event:example.org",
    "https://matrix.to/#/$event:example.org",
    "https://matrix.to/",
    "https://matrix.to/#/alice:example.org",
    "https://matrix.to/#/@alice",
    "https://matrix.to/#/@:example.org",
    "https://matrix.to/#/@alice:",
    "https://matrix.to/#/@alice:example.org%",
    "https://matrix.to/#/@alice:example.org%ZZ",
    "matrix:u/alice:example.org",
    "mailto:alice@example.org",
  ])
  func ignoresNonmentionOrMalformedDestinations(destination: String) {
    #expect(parseMarkdownMentions("[Alice](\(destination))").isEmpty)
  }

  @Test(arguments: [
    "@alice:example.org",
    "https://matrix.to/#/@alice:example.org",
    "<https://matrix.to/#/@alice:example.org>",
    "[Alice](https://example.org)",
    "![Alice](https://matrix.to/#/@alice:example.org)",
    #"\[Alice](https://matrix.to/#/@alice:example.org)"#,
    #"[Alice]\(https://matrix.to/#/@alice:example.org)"#,
    #"[Alice\](https://matrix.to/#/@alice:example.org)"#,
    "[Alice](https://matrix.to/#/@alice:example.org",
    "[Alice](",
    "[Alice]",
  ])
  func ignoresNonlinkOrEscapedSyntax(markdown: String) {
    #expect(parseMarkdownMentions(markdown).isEmpty)
  }

  @Test(arguments: [1, 2, 3, 4])
  func ignoresMentionsInsideInlineCode(backtickCount: Int) throws {
    let delimiter = String(repeating: "`", count: backtickCount)
    let hidden = "[Hidden](https://matrix.to/#/@hidden:example.org)"
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown = delimiter + hidden + delimiter + " " + visible

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test func inlineCodeRequiresMatchingBacktickRunLength() throws {
    let hidden = "[Hidden](https://matrix.to/#/@hidden:example.org)"
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown = "`` a ` \(hidden) ` b `` \(visible)"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test func inlineCodeCanSpanNewlines() throws {
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown = "`first line\n[Hidden](https://matrix.to/#/@hidden:example.org)\n` " + visible

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: ["```", "~~~", "   ```", "   ~~~"])
  func ignoresFencedCodeWithUpToThreeSpacesOfIndentation(fence: String) throws {
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown =
      "\(fence)swift\n[Hidden](https://matrix.to/#/@hidden:example.org)\n\(fence)\n\(visible)"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: ["`", "~"])
  func shorterFenceDoesNotCloseCodeBlock(marker: String) throws {
    let opening = String(repeating: marker, count: 4)
    let shorter = String(repeating: marker, count: 3)
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown =
      "\(opening)\n\(shorter)\n[Hidden](https://matrix.to/#/@hidden:example.org)\n\(opening)\n\(visible)"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: ["`", "~"])
  func longerFenceCanCloseCodeBlock(marker: String) throws {
    let opening = String(repeating: marker, count: 3)
    let closing = String(repeating: marker, count: 4)
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown =
      "\(opening)\n[Hidden](https://matrix.to/#/@hidden:example.org)\n\(closing)\n\(visible)"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: ["```", "~~~"])
  func otherFenceMarkerDoesNotCloseCodeBlock(opening: String) throws {
    let other = opening == "```" ? "~~~" : "```"
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown =
      "\(opening)\n\(other)\n[Hidden](https://matrix.to/#/@hidden:example.org)\n\(opening)\n\(visible)"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: ["```", "~~~", "   ````", "   ~~~~"])
  func unclosedFencedCodeIsIgnoredToEnd(fence: String) throws {
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let markdown = visible + "\n\(fence)\n[Hidden](https://matrix.to/#/@hidden:example.org)\n"

    try expectSingleMention(
      in: markdown, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test func mentionRangesLeaveAllOtherSourceUntouched() throws {
    let link = "[Alice &amp; Bob](https://matrix.to/#/@alice:example.org)"
    let prefix = "🌍 **Keep** &amp; [site](https://example.org)\n"
    let suffix = "\n![image](https://matrix.to/#/@image:example.org) `literal` &lt;end&gt;"
    let markdown = prefix + link + suffix
    let original = markdown
    let mentions = parseMarkdownMentions(markdown)

    #expect(markdown == original)
    #expect(mentions.count == 1)
    let mention = try #require(mentions.first)
    let replacementRange = try #require(Range(mention.range, in: markdown))
    var projected = markdown
    projected.replaceSubrange(replacementRange, with: "<mention>")
    #expect(projected == prefix + "<mention>" + suffix)
  }

  @Test func resumesAfterIgnoredAndMalformedLinks() throws {
    let visible = "[Alice](https://matrix.to/#/@alice:example.org)"
    let prefix =
      #"\[escaped](https://matrix.to/#/@escaped:example.org) ![image](https://matrix.to/#/@image:example.org) [bad](https://matrix.to/#/@bad) [site](https://example.org) "#

    try expectSingleMention(
      in: prefix + visible, link: visible, userID: "@alice:example.org", username: "Alice")
  }

  @Test(arguments: [
    "\\", "[", "[👩🏽‍💻", "[Alice]", "[Alice](", "[Alice](https://matrix.to/#/@alice:example.org\\",
    "`", "``", "```", "~~~", "\r", "\r\n", "   ",
  ])
  func handlesTruncatedSyntaxAtEndOfInput(suffix: String) {
    #expect(parseMarkdownMentions("👩🏽‍💻\n" + suffix).isEmpty)
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func preservesUTF16RangesAfterUnicodeCodeAndEscapes(newline: String) throws {
    let payload = UserDragPayload(userId: "@alice:example.org", username: "👩🏽‍💻 [Alice]")
    let visible = try #require(payload.markdownLink)
    let hidden = "[Hidden](https://matrix.to/#/@hidden:example.org)"
    let prefix =
      "🌍 e\u{301}" + newline + "   ```swift 👋" + newline + hidden + newline + "   ```"
      + newline + "``code 👩🏽‍💻`` " + #"\[escaped] "#

    try expectSingleMention(
      in: prefix + visible + "\\", link: visible, userID: payload.userId, username: payload.username
    )
  }

  @Test func recognizesSyntaxAdjacentToCombiningMarks() throws {
    let username = "\u{301}Alice"
    let link = "[\(username)](https://matrix.to/#/@alice:example.org)"
    let hidden = "[Hidden](https://matrix.to/#/@hidden:example.org)"
    let prefix = "`\u{301}\(hidden)` "
    let markdown = prefix + link + "\u{301}"
    let mentions = parseMarkdownMentions(markdown)

    #expect(mentions.count == 1)
    let mention = try #require(mentions.first)
    #expect(mention.userID == "@alice:example.org")
    #expect(mention.username == username)
    #expect(mention.range == NSRange(location: prefix.utf16.count, length: link.utf16.count))
    #expect((markdown as NSString).substring(with: mention.range) == link)
  }

  private func expectSingleMention(
    in markdown: String,
    link: String,
    userID: String,
    username: String
  ) throws {
    let mentions = parseMarkdownMentions(markdown)

    #expect(mentions.count == 1)
    let mention = try #require(mentions.first)
    #expect(mention.userID == userID)
    #expect(mention.username == username)
    #expect(mention.range == (markdown as NSString).range(of: link))
    let range = try #require(Range(mention.range, in: markdown))
    #expect(String(markdown[range]) == link)
  }
}

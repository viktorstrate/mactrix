import AppKit
import MatrixProtocols
import Testing

@testable import MactrixApp

@MainActor
struct ComposerMentionAutocompleteSessionTests {
  private struct Profile: UserProfile {
    let userId: String
    let displayName: String?
    var avatarUrl: String? { nil }
  }

  private typealias Session = ComposerMentionAutocompleteSession<Profile>

  private let alice = Profile(userId: "@alice:example.org", displayName: "Alice Wonderland")
  private let bob = Profile(userId: "@bob:example.org", displayName: nil)

  @Test func detectsMentionsOnlyAtValidCaretPositions() {
    #expect(detect("@") == query(""))
    #expect(detect("Hi @alice") == query("alice", location: 3))
    #expect(detect("Hi\n@alice") == query("alice", location: 3))
    #expect(detect("email@alice") == nil)
    #expect(detect("@alice ") == nil)
    #expect(detect("@alice", caret: 0) == nil)
    #expect(
      Session.Query.detect(
        in: NSAttributedString(string: "@alice"), selectedRange: NSRange(location: 1, length: 2))
        == nil)
  }

  @Test func includesWholeTokenUsingUTF16Ranges() {
    let text = "😀 @a😀 later"

    #expect(detect(text, caret: 5) == query("a😀", location: 3))
    #expect(detect(text, caret: 6) == nil)
  }

  @Test func attachmentsStopQueryScanning() {
    let text = NSMutableAttributedString(string: "@al")
    text.append(NSAttributedString(attachment: NSTextAttachment()))
    text.append(NSAttributedString(string: "ice"))

    #expect(Session.Query.detect(in: text, selectedRange: caret(3)) == query("al"))
    #expect(Session.Query.detect(in: text, selectedRange: caret(text.length)) == nil)
  }

  @Test func filtersNamesAndUserIDsCaseInsensitively() {
    let session = Session()
    update(session, "@")
    #expect(session.suggestions.map(\.userId) == [alice.userId, bob.userId])
    #expect(session.highlightedSuggestion?.userId == alice.userId)

    update(session, "@WONDER")
    #expect(session.suggestions.map(\.userId) == [alice.userId])

    update(session, "@BOB:EXAMPLE")
    #expect(session.suggestions.map(\.userId) == [bob.userId])

    update(session, "@nobody")
    #expect(session.query == query("nobody"))
    #expect(session.suggestions.isEmpty)
    #expect(session.highlightedSuggestion == nil)
  }

  @Test func preservesHighlightWhileUserRemainsSuggested() {
    let session = Session()
    update(session, "@")
    session.highlight(userID: bob.userId)

    update(session, "@EXAMPLE")
    #expect(session.highlightedUserID == bob.userId)

    update(session, "@ali")
    #expect(session.highlightedUserID == alice.userId)
  }

  @Test func dismissalSuppressesTokenUntilItEnds() {
    let session = Session()
    update(session, "@a")
    session.dismiss()

    update(session, "@alice")
    #expect(session.query == nil)
    #expect(session.suggestions.isEmpty)

    update(session, "@alice ")
    update(session, "@alice")
    #expect(session.highlightedSuggestion?.userId == alice.userId)
  }

  @Test func suspendsAutocompleteDuringComposition() {
    let session = Session()
    update(session, "@ali")

    update(session, "@ali", hasMarkedText: true)
    #expect(session.query == nil)
    #expect(session.suggestions.isEmpty)

    update(session, "@ali")
    #expect(session.highlightedSuggestion?.userId == alice.userId)
  }

  @Test func validatesReplacementAgainstCurrentTextAndSelection() {
    let session = Session()
    let text = NSAttributedString(string: "@alice")
    update(session, text.string)

    #expect(
      session.validatedReplacementRange(in: text, selectedRange: caret(3), hasMarkedText: false)
        == NSRange(location: 0, length: 6))
    #expect(
      session.validatedReplacementRange(
        in: NSAttributedString(string: "@alina"), selectedRange: caret(3), hasMarkedText: false)
        == nil)
    #expect(
      session.validatedReplacementRange(in: text, selectedRange: caret(0), hasMarkedText: false)
        == nil)
    #expect(
      session.validatedReplacementRange(in: text, selectedRange: caret(6), hasMarkedText: true)
        == nil)
  }

  private func update(_ session: Session, _ text: String, hasMarkedText: Bool = false) {
    let attributed = NSAttributedString(string: text)
    session.update(
      in: attributed, selectedRange: caret(attributed.length), hasMarkedText: hasMarkedText,
      candidates: [alice, bob])
  }

  private func detect(_ text: String, caret position: Int? = nil) -> Session.Query? {
    let attributed = NSAttributedString(string: text)
    return Session.Query.detect(
      in: attributed, selectedRange: caret(position ?? attributed.length))
  }

  private func caret(_ location: Int) -> NSRange {
    NSRange(location: location, length: 0)
  }

  private func query(_ text: String, location: Int = 0) -> Session.Query {
    .init(range: NSRange(location: location, length: 1 + text.utf16.count), text: text)
  }
}

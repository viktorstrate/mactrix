import AppKit
import MatrixProtocols
import Testing

@testable import MactrixApp

@MainActor
struct ComposerMentionAutocompleteSessionTests {
  private struct Profile: UserProfile {
    let userId: String
    let displayName: String?
    var avatarUrl: String? = nil
  }

  private let alice = Profile(userId: "@alice:example.org", displayName: "Alice")
  private let bob = Profile(userId: "@bob:example.org", displayName: "Bob")

  @Test func startsInactive() {
    let session = ComposerMentionAutocompleteSession<Profile>()

    #expect(session.query == nil)
    #expect(session.suggestions.isEmpty)
    #expect(session.highlightedSuggestion == nil)
    #expect(session.dismissedTriggerLocation == nil)
  }

  @Test func queryTracksRangeAndHighlightsFirstSuggestion() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    let query = query("a", location: 3)

    session.update(query: query, suggestions: [alice, bob])

    #expect(session.query == query)
    #expect(session.suggestions.map(\.userId) == [alice.userId, bob.userId])
    #expect(session.highlightedSuggestion?.userId == alice.userId)
  }

  @Test func highlightFollowsUserIdentityAcrossUpdates() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query(""), suggestions: [alice, bob])
    session.highlight(userID: bob.userId)

    session.update(query: query("b"), suggestions: [bob, alice])

    #expect(session.highlightedUserID == bob.userId)

    session.update(query: query("a"), suggestions: [alice])

    #expect(session.highlightedUserID == alice.userId)
    session.highlight(userID: "@unknown:example.org")
    #expect(session.highlightedUserID == alice.userId)
  }

  @Test func profilesPreserveOptionalNamesAndAvatars() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    let profile = Profile(
      userId: "@unnamed:example.org", displayName: nil, avatarUrl: "mxc://example.org/avatar")
    let profile2 = Profile(
      userId: "@another:example.org", displayName: nil, avatarUrl: "mxc://test.org/avatar")

    session.update(query: query(""), suggestions: [profile, profile2])

    #expect(session.highlightedSuggestion?.userId == profile.userId)
    #expect(session.highlightedSuggestion?.displayName == nil)
    #expect(session.highlightedSuggestion?.avatarUrl == profile.avatarUrl)
    #expect(session.suggestions.count == 2)
  }

  @Test func emptySuggestionsHaveNoHighlight() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query(""), suggestions: [alice])

    session.update(query: query("unknown"), suggestions: [])

    #expect(session.query != nil)
    #expect(session.highlightedUserID == nil)
    #expect(session.highlightedSuggestion == nil)
  }

  @Test func newTriggerStartsWithFirstSuggestion() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query(""), suggestions: [alice, bob])
    session.highlight(userID: bob.userId)

    session.update(query: query("", location: 10), suggestions: [alice, bob])

    #expect(session.highlightedUserID == alice.userId)
  }

  @Test func dismissalSuppressesSameTokenUntilItEnds() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query("a"), suggestions: [alice])

    session.dismiss()
    session.dismiss()
    session.update(query: query("al"), suggestions: [alice])

    #expect(session.query == nil)
    #expect(session.suggestions.isEmpty)
    #expect(session.highlightedUserID == nil)
    #expect(session.dismissedTriggerLocation == 0)

    session.update(query: nil, suggestions: [])
    session.update(query: query("a"), suggestions: [alice])

    #expect(session.query == query("a"))
    #expect(session.highlightedUserID == alice.userId)
    #expect(session.dismissedTriggerLocation == nil)
  }

  @Test func differentTriggerIsNotSuppressed() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query("a"), suggestions: [alice])
    session.dismiss()

    session.update(query: query("b", location: 10), suggestions: [bob])

    #expect(session.query == query("b", location: 10))
    #expect(session.highlightedUserID == bob.userId)
    #expect(session.dismissedTriggerLocation == nil)
  }

  @Test func resetClearsDismissal() {
    let session = ComposerMentionAutocompleteSession<Profile>()
    session.update(query: query("a"), suggestions: [alice])
    session.dismiss()

    session.reset()

    #expect(session.query == nil)
    #expect(session.suggestions.isEmpty)
    #expect(session.highlightedUserID == nil)
    #expect(session.dismissedTriggerLocation == nil)
  }

  private func query(
    _ text: String, location: Int = 0
  ) -> ComposerMentionAutocompleteSession<Profile>.Query {
    .init(range: NSRange(location: location, length: 1 + text.utf16.count), text: text)
  }
}

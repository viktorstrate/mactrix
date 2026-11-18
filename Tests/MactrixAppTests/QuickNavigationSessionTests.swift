import Testing

@testable import MactrixApp

@MainActor
struct QuickNavigationSessionTests {
  private let general = QuickNavigationCandidate(
    id: "!general:example.org", displayName: "General", canonicalAlias: "#lobby:example.org")
  private let development = QuickNavigationCandidate(
    id: "!development:example.org", displayName: "Development", canonicalAlias: "#dev:example.org")
  private let design = QuickNavigationCandidate(
    id: "!design:example.org", displayName: "Design", canonicalAlias: nil)

  @Test func startsWithNoResultsOrSelection() {
    let session = QuickNavigationSession()
    #expect(session.query.isEmpty)
    #expect(session.results.isEmpty)
    #expect(session.highlightedRoomID == nil)
    #expect(session.highlightedCandidate == nil)
    session.moveSelection(.up)
    session.moveSelection(.down)
    #expect(session.highlightedRoomID == nil)
  }

  @Test func emptyQueryPreservesAllCandidatesInRoomListOrder() {
    let session = QuickNavigationSession()
    let unnamed = QuickNavigationCandidate(
      id: "!unnamed:example.org", displayName: nil, canonicalAlias: nil)
    let emptyName = QuickNavigationCandidate(
      id: "!empty:example.org", displayName: "", canonicalAlias: "")
    let candidates = [design, general, development, unnamed, emptyName]
    session.updateCandidates(candidates)

    #expect(session.results == candidates)
    #expect(session.highlightedCandidate == design)
    session.updateQuery(" \n\t ")
    #expect(session.results == candidates)
  }

  @Test func filtersUsingSubsequencesNotJustSubstrings() {
    let session = makeSession()
    session.updateQuery("dvlp")
    #expect(session.results == [development])
    #expect(session.highlightedCandidate == development)

    session.updateQuery("plvd")
    #expect(session.results.isEmpty)
    #expect(session.highlightedRoomID == nil)
    #expect(session.highlightedCandidate == nil)
  }

  @Test func searchesAliasesAndRoomIDsWithoutNames() {
    let session = makeSession()
    session.updateQuery("#lby")
    #expect(session.results == [general])

    let unnamed = QuickNavigationCandidate(
      id: "!unique:matrix.test", displayName: nil, canonicalAlias: nil)
    session.updateCandidates([general, unnamed])
    session.updateQuery("!uq:mt")
    #expect(session.results == [unnamed])
  }

  @Test func normalizesCaseDiacriticsAndCanonicalUnicode() {
    let session = QuickNavigationSession()
    let cafe = room("Café Développement")
    let decomposed = room("Cafe\u{301} De\u{301}veloppement")
    session.updateCandidates([cafe, decomposed])
    session.updateQuery("CAFE DEV")
    #expect(session.results == [cafe, decomposed])

    session.updateQuery("café dév")
    #expect(session.results == [cafe, decomposed])
  }

  @Test func supportsNonLatinTextAndExtendedGraphemeClusters() {
    let session = QuickNavigationSession()
    let japanese = room("日本語の部屋")
    let emoji = room("👩🏽‍💻 Development 🚀")
    session.updateCandidates([japanese, emoji])
    session.updateQuery("日本部屋")
    #expect(session.results == [japanese])
    session.updateQuery("👩🏽‍💻🚀")
    #expect(session.results == [emoji])
  }

  @Test func trimsSurroundingQueryWhitespace() {
    let session = makeSession()
    session.updateQuery("  dvlp\n")
    #expect(session.query == "  dvlp\n")
    #expect(session.results == [development])
  }

  @Test func exactMatchesBeatPrefixesWhichBeatOtherSubsequences() {
    let session = QuickNavigationSession()
    let exact = room("Dev")
    let prefix = room("Development")
    let subsequence = room("Daily events")
    session.updateCandidates([subsequence, prefix, exact])
    session.updateQuery("dev")
    #expect(session.results == [exact, prefix, subsequence])
  }

  @Test func nameMatchesBeatAliasMatchesWhichBeatRoomIDMatches() {
    let session = QuickNavigationSession()
    let name = QuickNavigationCandidate(
      id: "!a:example.org", displayName: "My Destination", canonicalAlias: nil)
    let alias = QuickNavigationCandidate(
      id: "!b:example.org", displayName: "Other", canonicalAlias: "#destination:example.org")
    let id = QuickNavigationCandidate(
      id: "!destination:example.org", displayName: "Other", canonicalAlias: nil)
    session.updateCandidates([id, alias, name])
    session.updateQuery("destination")
    #expect(session.results == [name, alias, id])
  }

  @Test func wordBoundariesBeatMidWordMatches() {
    let session = QuickNavigationSession()
    let boundary = room("X ab cd")
    let midWord = room("X abxcd")
    session.updateCandidates([midWord, boundary])
    session.updateQuery("abcd")
    #expect(session.results == [boundary, midWord])
  }

  @Test func consecutiveCharactersBeatGappedCharacters() {
    let session = QuickNavigationSession()
    let consecutive = room("X abcd")
    let gapped = room("X a b c d")
    session.updateCandidates([gapped, consecutive])
    session.updateQuery("abcd")
    #expect(session.results == [consecutive, gapped])
  }

  @Test func smallerGapsRankHigher() {
    let session = QuickNavigationSession()
    let smallGap = room("X abxcd")
    let largeGap = room("X abxxxxcd")
    session.updateCandidates([largeGap, smallGap])
    session.updateQuery("abcd")
    #expect(session.results == [smallGap, largeGap])
  }

  @Test func findsBetterAlignmentAfterAnEarlierLooseMatch() {
    let session = QuickNavigationSession()
    let laterMatch = room("a---b abc")
    let looseMatch = room("a---b--c")
    session.updateCandidates([looseMatch, laterMatch])
    session.updateQuery("abc")
    #expect(session.results == [laterMatch, looseMatch])
  }

  @Test func tiedScoresPreserveRoomListOrder() {
    let session = QuickNavigationSession()
    let first = QuickNavigationCandidate(
      id: "!first:example.org", displayName: "Team", canonicalAlias: nil)
    let second = QuickNavigationCandidate(
      id: "!second:example.org", displayName: "Team", canonicalAlias: nil)
    session.updateCandidates([second, first])
    session.updateQuery("tm")
    #expect(session.results == [second, first])
    session.updateCandidates([first, second])
    #expect(session.results == [first, second])
  }

  @Test func arrowsStopAtSelectionBoundaries() {
    let session = makeSession()
    session.moveSelection(.up)
    #expect(session.highlightedCandidate == general)
    session.moveSelection(.down)
    #expect(session.highlightedCandidate == development)
    session.moveSelection(.down)
    session.moveSelection(.down)
    #expect(session.highlightedCandidate == design)
    session.moveSelection(.up)
    #expect(session.highlightedCandidate == development)
  }

  @Test func queryChangesSelectFirstResultAndClearingRestoresRoomListOrder() {
    let session = makeSession()
    session.highlight(roomID: design.id)
    session.updateQuery("de")
    #expect(session.highlightedCandidate == development)
    session.highlight(roomID: design.id)
    session.updateQuery("de")
    #expect(session.highlightedCandidate == design)
    session.updateQuery("")
    #expect(session.results == [general, development, design])
    #expect(session.highlightedCandidate == general)
  }

  @Test func ignoresHighlightRequestsForMissingOrFilteredRooms() {
    let session = makeSession()
    session.highlight(roomID: "!missing:example.org")
    #expect(session.highlightedCandidate == general)
    session.updateQuery("dvlp")
    session.highlight(roomID: general.id)
    #expect(session.highlightedCandidate == development)
  }

  @Test func candidateUpdatesPreserveSelectionByRoomIDAndRefreshMetadata() {
    let session = makeSession()
    session.updateQuery("de")
    session.highlight(roomID: design.id)
    let renamed = QuickNavigationCandidate(
      id: design.id, displayName: "Design Team", canonicalAlias: "#design:example.org")
    session.updateCandidates([renamed, development, general])
    #expect(session.highlightedRoomID == design.id)
    #expect(session.highlightedCandidate == renamed)
    #expect(session.results == [renamed, development])
  }

  @Test func avatarAndKindUpdatesPreserveQueryAndHighlightedRoom() {
    let session = makeSession()
    session.updateQuery("de")
    session.highlight(roomID: design.id)
    let updated = QuickNavigationCandidate(
      id: design.id, displayName: design.displayName, canonicalAlias: design.canonicalAlias,
      avatarUrl: "mxc://example.org/alice", kind: .direct)
    session.updateCandidates([general, development, updated])

    #expect(session.query == "de")
    #expect(session.highlightedCandidate == updated)
    #expect(session.highlightedCandidate?.avatarUrl == "mxc://example.org/alice")
    #expect(session.highlightedCandidate?.kind == .direct)

    session.updateCandidates([general, development, design])
    #expect(session.highlightedCandidate == design)
    #expect(session.highlightedCandidate?.avatarUrl == nil)
    #expect(session.highlightedCandidate?.kind == .room)
  }

  @Test func removedOrNoLongerMatchingSelectionFallsBackToFirstResult() {
    let session = makeSession()
    session.highlight(roomID: design.id)
    session.updateCandidates([development, general])
    #expect(session.highlightedCandidate == development)

    session.updateQuery("engineering")
    #expect(session.highlightedCandidate == nil)
    let renamed = QuickNavigationCandidate(
      id: development.id, displayName: "Engineering", canonicalAlias: nil)
    let otherMatch = room("Engineering Team")
    session.updateCandidates([renamed, otherMatch, general])
    #expect(session.highlightedCandidate == renamed)
    session.updateCandidates([development, otherMatch, general])
    #expect(session.highlightedCandidate == otherMatch)
  }

  @Test func clearingCandidatesClearsSelectionAndNewCandidatesUseExistingQuery() {
    let session = makeSession()
    session.updateQuery("dvlp")
    session.updateCandidates([])
    #expect(session.results.isEmpty)
    #expect(session.highlightedRoomID == nil)
    session.moveSelection(.down)
    #expect(session.highlightedRoomID == nil)
    session.updateCandidates([general, development])
    #expect(session.results == [development])
    #expect(session.highlightedCandidate == development)
  }

  @Test func longerQueriesAndRepeatedCharactersRequireCompleteOrderedMatches() {
    let session = QuickNavigationSession()
    let candidate = QuickNavigationCandidate(id: "!x", displayName: "aba", canonicalAlias: nil)
    session.updateCandidates([candidate])
    session.updateQuery("aa")
    #expect(session.results == [candidate])
    session.updateQuery("aaa")
    #expect(session.results.isEmpty)
    session.updateQuery("abababab")
    #expect(session.results.isEmpty)
  }

  private func makeSession() -> QuickNavigationSession {
    let session = QuickNavigationSession()
    session.updateCandidates([general, development, design])
    return session
  }

  private func room(_ name: String) -> QuickNavigationCandidate {
    QuickNavigationCandidate(id: "!\(name):example.org", displayName: name, canonicalAlias: nil)
  }
}

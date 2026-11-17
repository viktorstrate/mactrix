import Foundation
import Observation

/// Searchable room metadata, independent of membership state and the Matrix SDK.
struct QuickNavigationCandidate: Equatable, Identifiable, Sendable {
  let id: String
  let displayName: String?
  let canonicalAlias: String?
}

/// Query, ranking, and keyboard selection without any window or view dependencies.
@MainActor @Observable
final class QuickNavigationSession {
  enum SelectionDirection {
    case up
    case down
  }

  private(set) var query = ""
  private(set) var results: [QuickNavigationCandidate] = []
  private(set) var highlightedRoomID: String?

  @ObservationIgnored private var candidates: [IndexedCandidate] = []

  var highlightedCandidate: QuickNavigationCandidate? {
    results.first { $0.id == highlightedRoomID }
  }

  /// Accepts the complete room list in its original order, without destination exclusions.
  func updateCandidates(_ candidates: [QuickNavigationCandidate]) {
    self.candidates = candidates.map(IndexedCandidate.init)
    updateResults(preserving: highlightedRoomID)
  }

  func updateQuery(_ query: String) {
    guard self.query != query else { return }
    self.query = query
    updateResults(preserving: nil)
  }

  func highlight(roomID: String) {
    guard results.contains(where: { $0.id == roomID }) else { return }
    highlightedRoomID = roomID
  }

  func moveSelection(_ direction: SelectionDirection) {
    guard !results.isEmpty else { return }
    let current = results.firstIndex { $0.id == highlightedRoomID } ?? 0
    let offset = direction == .down ? 1 : -1
    let next = min(max(current + offset, 0), results.count - 1)
    highlightedRoomID = results[next].id
  }

  private func updateResults(preserving roomID: String?) {
    let normalizedQuery = SearchText.normalize(
      query.trimmingCharacters(in: .whitespacesAndNewlines))
    if normalizedQuery.isEmpty {
      results = candidates.map(\.candidate)
    } else {
      results = candidates.enumerated().compactMap { index, candidate in
        candidate.rank(for: normalizedQuery).map { (index, candidate.candidate, $0) }
      }.sorted { lhs, rhs in
        if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
        return lhs.0 < rhs.0
      }.map { $0.1 }
    }
    highlightedRoomID = results.first { $0.id == roomID }?.id ?? results.first?.id
  }
}

private struct IndexedCandidate {
  let candidate: QuickNavigationCandidate
  let fields: [SearchText]

  init(_ candidate: QuickNavigationCandidate) {
    self.candidate = candidate
    fields = [candidate.displayName, candidate.canonicalAlias, candidate.id].map {
      SearchText($0 ?? "")
    }
  }

  func rank(for query: [Character]) -> SearchRank? {
    // A name match takes precedence over aliases, then room IDs.
    for (index, field) in fields.enumerated() {
      if let match = field.match(query) {
        return SearchRank(fieldPriority: fields.count - index, match: match)
      }
    }
    return nil
  }
}

private struct SearchRank: Comparable {
  let fieldPriority: Int
  let match: SearchMatch

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.fieldPriority != rhs.fieldPriority { return lhs.fieldPriority < rhs.fieldPriority }
    return lhs.match < rhs.match
  }
}

private struct SearchMatch: Comparable {
  /// Exact, prefix, and other subsequence matches, in descending preference.
  let category: Int
  let score: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.category != rhs.category { return lhs.category < rhs.category }
    return lhs.score < rhs.score
  }
}

private struct SearchText {
  let characters: [Character]

  init(_ text: String) {
    characters = Self.normalize(text)
  }

  static func normalize(_ text: String) -> [Character] {
    Array(
      text.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")))
  }

  func match(_ query: [Character]) -> SearchMatch? {
    guard query.count <= characters.count else { return nil }
    if characters == query { return SearchMatch(category: 2, score: 0) }
    if characters.starts(with: query) { return SearchMatch(category: 1, score: 0) }

    // Keep the best score ending at each character, rather than greedily choosing the first
    // occurrence. This lets a later consecutive or word-boundary match beat an earlier loose one.
    // A running best gapped predecessor keeps matching O(query length × field length).
    var previous = [Int?](repeating: nil, count: characters.count)
    for (queryIndex, character) in query.enumerated() {
      var current = [Int?](repeating: nil, count: characters.count)
      var bestGappedPredecessor: Int?
      for index in characters.indices {
        if index >= 2, let score = previous[index - 2] {
          bestGappedPredecessor = max(bestGappedPredecessor ?? Int.min, score + index - 2)
        }
        guard characters[index] == character else { continue }
        let isBoundary =
          index == 0 || (!characters[index - 1].isLetter && !characters[index - 1].isNumber)
        let bonus = 10 + (isBoundary ? 8 : 0)
        if queryIndex == 0 {
          current[index] = bonus - index
        } else {
          if let bestGappedPredecessor {
            current[index] = bestGappedPredecessor - index + 1 + bonus
          }
          if index > 0, let adjacent = previous[index - 1] {
            current[index] = max(current[index] ?? Int.min, adjacent + 12 + bonus)
          }
        }
      }
      previous = current
    }
    return previous.compactMap { $0 }.max().map { SearchMatch(category: 0, score: $0) }
  }
}

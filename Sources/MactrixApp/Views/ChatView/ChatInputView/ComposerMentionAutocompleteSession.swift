import AppKit
import MatrixProtocols

/// Editor-local query and suggestion state, independent of suggestion presentation.
@MainActor @Observable
final class ComposerMentionAutocompleteSession<UserProfile: MatrixProtocols.UserProfile> {
  struct Query: Equatable {
    /// UTF-16 range of the entire mention token, including its leading @.
    let range: NSRange
    let text: String

    static func detect(in text: NSAttributedString, selectedRange: NSRange) -> Self? {
      let string = text.string as NSString
      let caret = selectedRange.location
      guard selectedRange.length == 0, caret > 0, caret <= string.length,
        caret == string.length || !UTF16.isTrailSurrogate(string.character(at: caret))
      else { return nil }

      func isWhitespace(at index: Int) -> Bool {
        guard let scalar = UnicodeScalar(string.character(at: index)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
      }

      func isBoundary(at index: Int) -> Bool {
        string.character(at: index) == 0xFFFC || isWhitespace(at: index)
          || text.attribute(.attachment, at: index, effectiveRange: nil) != nil
      }

      var start = caret
      while start > 0, !isBoundary(at: start - 1) { start -= 1 }
      guard start < caret, string.character(at: start) == 0x40,
        start == 0
          || (isWhitespace(at: start - 1)
            && text.attribute(.attachment, at: start - 1, effectiveRange: nil) == nil)
      else { return nil }

      // Include the suffix when the caret is inside a token so acceptance replaces it too.
      var end = caret
      while end < string.length, !isBoundary(at: end) { end += 1 }
      return Self(
        range: NSRange(location: start, length: end - start),
        text: string.substring(with: NSRange(location: start + 1, length: end - start - 1)))
    }
  }

  private(set) var query: Query?
  private(set) var suggestions: [UserProfile] = []
  private(set) var highlightedUserID: String?
  private(set) var dismissedTriggerLocation: Int?

  var highlightedSuggestion: UserProfile? {
    suggestions.first { $0.userId == highlightedUserID }
  }

  func update(
    in text: NSAttributedString, selectedRange: NSRange, hasMarkedText: Bool,
    candidates: [UserProfile]
  ) {
    guard !hasMarkedText, let query = Query.detect(in: text, selectedRange: selectedRange) else {
      reset()
      return
    }
    let suggestions = candidates.filter { candidate in
      query.text.isEmpty
        || candidate.displayName?.range(of: query.text, options: .caseInsensitive) != nil
        || candidate.userId.range(of: query.text, options: .caseInsensitive) != nil
    }
    update(query: query, suggestions: suggestions)
  }

  /// Re-read the editor immediately before accepting; stored ranges can be stale after an edit.
  func validatedReplacementRange(
    in text: NSAttributedString, selectedRange: NSRange, hasMarkedText: Bool
  ) -> NSRange? {
    guard !hasMarkedText, let query,
      Query.detect(in: text, selectedRange: selectedRange) == query
    else { return nil }
    return query.range
  }

  func update(query: Query?, suggestions: [UserProfile]) {
    guard let query else {
      reset()
      return
    }
    // Keep an explicitly dismissed token suppressed as its query text changes.
    guard query.range.location != dismissedTriggerLocation else { return }

    let previousHighlight =
      self.query?.range.location == query.range.location
      ? highlightedUserID : nil
    self.query = query
    self.suggestions = suggestions
    dismissedTriggerLocation = nil
    highlightedUserID =
      suggestions.first { $0.userId == previousHighlight }?.userId
      ?? suggestions.first?.userId
  }

  func highlight(userID: String) {
    guard suggestions.contains(where: { $0.userId == userID }) else { return }
    highlightedUserID = userID
  }

  func dismiss() {
    guard let query else { return }
    let location = query.range.location
    reset()
    dismissedTriggerLocation = location
  }

  /// End the token's lifetime, allowing a future query at the same location.
  func reset() {
    query = nil
    suggestions = []
    highlightedUserID = nil
    dismissedTriggerLocation = nil
  }
}

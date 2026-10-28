import Foundation
import MatrixProtocols

/// Editor-local state; query detection and suggestion presentation are handled separately.
@MainActor
final class ComposerMentionAutocompleteSession<UserProfile: MatrixProtocols.UserProfile> {
  struct Query: Equatable {
    /// UTF-16 range of the entire mention token, including its leading @.
    let range: NSRange
    let text: String
  }

  private(set) var query: Query?
  private(set) var suggestions: [UserProfile] = []
  private(set) var highlightedUserID: String?
  private(set) var dismissedTriggerLocation: Int?

  var highlightedSuggestion: (UserProfile)? {
    suggestions.first { $0.userId == highlightedUserID }
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

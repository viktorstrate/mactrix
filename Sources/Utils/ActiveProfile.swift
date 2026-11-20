import Foundation

/// Process-global holder for the currently active profile.
///
/// Defaults to ``Profile/default`` so that tests, previews, and launches without `--profile`
/// keep exactly today's legacy behaviour.
public enum ActiveProfile {
  nonisolated(unsafe) public static var current: Profile = .default
}

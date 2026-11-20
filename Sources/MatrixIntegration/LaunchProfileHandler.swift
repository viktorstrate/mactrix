import Foundation
import Utils

/// The result of handling profile-related command-line arguments.
public enum LaunchDisposition: Equatable {
  case `continue`
  case exit(code: Int32)
}

/// Parses profile-related command-line arguments and performs the requested action.
///
/// - Returns `.continue` when the app should launch normally.
/// - Returns `.exit(code:)` for `--help`, `--list-profiles`, `--delete-profile`, or errors.
public func handleLaunchProfileArguments(
  arguments: [String] = CommandLine.arguments,
  env: [String: String] = ProcessInfo.processInfo.environment
) -> LaunchDisposition {
  do {
    switch try Profile.selected(from: arguments, env: env) {
    case .help:
      print(Profile.usage)
      return .exit(code: 0)

    case .listProfiles:
      let profiles = try Profile.list()
      for profile in profiles {
        if profile.isDefault {
          print("\(profile.name) (main profile)")
        } else if let createdAt = profile.createdAt() {
          print("\(profile.name)\tcreatedAt: \(createdAt)")
        } else {
          print(profile.name)
        }
      }
      return .exit(code: 0)

    case .deleteProfile(let name):
      try Profile.delete(name: name) { service in
        try AppKeychain(service: service).removeAll()
      }
      print(
        "Deleted profile '\(name)'. This wiped its encryption keys and session data.")
      return .exit(code: 0)

    case .profile(let profile):
      try profile.ensureExists()
      ActiveProfile.current = profile
      return .continue

    case .none:
      return .continue
    }
  } catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    return .exit(code: 2)
  }
}

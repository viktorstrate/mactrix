import Foundation

/// Errors raised by profile parsing and management.
public enum ProfileError: Error, Equatable, Sendable {
  case invalidName(String)
  case reservedName(String)
  case missingProfileValue
  case missingDeleteProfileValue
  case defaultProfileCannotBeNamed
  case cannotDeleteDefaultProfile
  case directoryOperationFailed(underlying: Error)

  public static func == (lhs: ProfileError, rhs: ProfileError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidName(let a), .invalidName(let b)): return a == b
    case (.reservedName(let a), .reservedName(let b)): return a == b
    case (.missingProfileValue, .missingProfileValue): return true
    case (.missingDeleteProfileValue, .missingDeleteProfileValue): return true
    case (.defaultProfileCannotBeNamed, .defaultProfileCannotBeNamed): return true
    case (.cannotDeleteDefaultProfile, .cannotDeleteDefaultProfile): return true
    case (.directoryOperationFailed, .directoryOperationFailed): return true
    default: return false
    }
  }
}

extension ProfileError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidName(let name):
      return "Invalid profile name: '\(name)'. Names must be 1-64 characters, contain only A-Z, a-z, 0-9, '.', '_', '-', and not start with '.'."
    case .reservedName(let name):
      return "'\(name)' is a reserved profile name. Omit --profile to use the main profile."
    case .missingProfileValue:
      return "--profile requires a value, e.g. --profile test-server."
    case .missingDeleteProfileValue:
      return "--delete-profile requires a value, e.g. --delete-profile test-server."
    case .defaultProfileCannotBeNamed:
      return "Use the main profile by omitting --profile, not by naming it 'default'."
    case .cannotDeleteDefaultProfile:
      return "The main profile cannot be deleted."
    case .directoryOperationFailed(let underlying):
      return "Profile directory operation failed: \(underlying.localizedDescription)"
    }
  }
}

/// The result of inspecting the process arguments/environment for profile-related options.
public enum ProfileSelection: Equatable, Sendable {
  case none
  case profile(Profile)
  case listProfiles
  case deleteProfile(String)
  case help
}

/// A Matrix data/profile namespace.
///
/// The ``Profile/default`` instance maps exactly to today's legacy paths and keychain service.
/// Named profiles live under `profiles/<name>` in both Application Support and Caches.
public struct Profile: Equatable, Hashable, Sendable {
  public static func == (lhs: Profile, rhs: Profile) -> Bool {
    lhs.name == rhs.name
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  public static let fallbackName = "default"
  public static let reservedNames: Set<String> = [fallbackName, ".", ".."]

  /// 1...64 chars of [A-Za-z0-9._-], must not start with '.'.
  public static let namePattern = "^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"

  public let name: String
  public let isDefault: Bool
  public let applicationSupportRoot: URL
  public let cachesRoot: URL

  /// The main profile. Uses exactly the legacy paths and keychain service.
  public static let `default` = Profile(
    name: fallbackName,
    applicationSupportRoot: URL.applicationSupportDirectory,
    cachesRoot: URL.cachesDirectory
  )

  /// Returns the main profile with injectable roots (used by tests).
  public static func defaultProfile(
    applicationSupportRoot: URL,
    cachesRoot: URL
  ) -> Profile {
    Profile(name: fallbackName, applicationSupportRoot: applicationSupportRoot, cachesRoot: cachesRoot)
  }

  /// Creates a named profile after validating the name.
  public static func named(_ name: String) throws -> Profile {
    try named(name, applicationSupportRoot: URL.applicationSupportDirectory, cachesRoot: URL.cachesDirectory)
  }

  /// Creates a named profile with injectable roots (used by tests).
  public static func named(
    _ name: String,
    applicationSupportRoot: URL,
    cachesRoot: URL
  ) throws -> Profile {
    try validate(name: name)
    return Profile(
      name: name,
      applicationSupportRoot: applicationSupportRoot,
      cachesRoot: cachesRoot
    )
  }

  private init(name: String, applicationSupportRoot: URL, cachesRoot: URL) {
    self.name = name
    self.isDefault = name == Self.fallbackName
    self.applicationSupportRoot = applicationSupportRoot
    self.cachesRoot = cachesRoot
  }

  private static func validate(name: String) throws {
    if reservedNames.contains(name) {
      throw ProfileError.reservedName(name)
    }
    guard name.range(of: namePattern, options: .regularExpression) != nil else {
      throw ProfileError.invalidName(name)
    }
  }

  // MARK: - Paths

  private static let bundleID = Bundle.main.bundleIdentifier ?? "dk.qpqp.mactrix"

  private var applicationSupportBundleRoot: URL {
    applicationSupportRoot.appending(component: Self.bundleID)
  }

  private var cachesBundleRoot: URL {
    cachesRoot.appending(component: Self.bundleID)
  }

  /// The profile's container directory in Application Support.
  ///
  /// For the default profile this is the legacy root `.../dk.qpqp.mactrix`.
  /// For named profiles this is `.../dk.qpqp.mactrix/profiles/<name>`.
  public var directory: URL {
    if isDefault {
      return applicationSupportBundleRoot
    }
    return applicationSupportBundleRoot
      .appending(component: "profiles")
      .appending(component: name)
  }

  /// The directory that holds per-storeID data directories.
  ///
  /// Default: `.../dk.qpqp.mactrix/<storeID>`.
  /// Named:   `.../dk.qpqp.mactrix/profiles/<name>/data/<storeID>`.
  public func dataDirectory(storeID: String) -> URL {
    if isDefault {
      return directory.appending(component: storeID)
    }
    return directory.appending(component: "data").appending(component: storeID)
  }

  /// The directory that holds per-storeID cache directories.
  ///
  /// Default: `.../Caches/dk.qpqp.mactrix/<storeID>`.
  /// Named:   `.../Caches/dk.qpqp.mactrix/profiles/<name>/cache/<storeID>`.
  public func cacheDirectory(storeID: String) -> URL {
    if isDefault {
      return cachesBundleRoot.appending(component: storeID)
    }
    return cachesBundleRoot
      .appending(component: "profiles")
      .appending(component: name)
      .appending(component: "cache")
      .appending(component: storeID)
  }

  /// The root of all cache directories for this profile (used for deletion).
  private var cacheRoot: URL {
    if isDefault {
      return cachesBundleRoot
    }
    return cachesBundleRoot.appending(component: "profiles").appending(component: name)
  }

  // MARK: - Keychain

  /// The keychain service name for this profile.
  ///
  /// Default: the bundle identifier (today's value).
  /// Named:   `<bundleID>.profile.<name>`.
  public var keychainService: String {
    if isDefault {
      return Self.bundleID
    }
    return "\(Self.bundleID).profile.\(name)"
  }

  // MARK: - Lifecycle

  /// Creates the profile directory and writes `profile.json` if this is a named profile.
  /// Idempotent: calling it on an existing profile is a no-op.
  public func ensureExists() throws {
    guard !isDefault else { return }

    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)

    let profileJSON = directory.appending(component: "profile.json")
    guard !fm.fileExists(atPath: profileJSON.path(percentEncoded: false)) else { return }

    let info = ProfileInfo(
      name: name,
      schemaVersion: 1,
      createdAt: ISO8601DateFormatter().string(from: Date())
    )
    let data = try JSONEncoder().encode(info)
    try data.write(to: profileJSON, options: .atomic)
  }

  /// Returns the `createdAt` timestamp from `profile.json`, or `nil` for the default profile.
  public func createdAt() -> String? {
    guard !isDefault else { return nil }
    let profileJSON = directory.appending(component: "profile.json")
    let fm = FileManager.default
    guard fm.fileExists(atPath: profileJSON.path(percentEncoded: false)) else { return nil }
    guard let data = fm.contents(atPath: profileJSON.path(percentEncoded: false)) else { return nil }
    guard let info = try? JSONDecoder().decode(ProfileInfo.self, from: data) else { return nil }
    return info.createdAt
  }

  /// Lists all known profiles, including the synthetic default profile.
  public static func list(
    applicationSupportRoot: URL = URL.applicationSupportDirectory,
    cachesRoot: URL = URL.cachesDirectory
  ) throws -> [Profile] {
    let profilesRoot = applicationSupportRoot
      .appending(component: bundleID)
      .appending(component: "profiles")

    var result: [Profile] = [.default]
    let fm = FileManager.default
    guard fm.fileExists(atPath: profilesRoot.path(percentEncoded: false)) else { return result }

    let contents = try fm.contentsOfDirectory(
      at: profilesRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: .skipsHiddenFiles
    )

    for url in contents {
      let profileName = url.lastPathComponent
      let profileJSON = url.appending(component: "profile.json")
      guard fm.fileExists(atPath: profileJSON.path(percentEncoded: false)) else { continue }

      do {
        try validate(name: profileName)
        result.append(
          Profile(
            name: profileName,
            applicationSupportRoot: applicationSupportRoot,
            cachesRoot: cachesRoot
          )
        )
      } catch {
        // Ignore directories that don't represent valid profiles.
        continue
      }
    }

    return result
  }

  /// Deletes a named profile's Application Support and Caches directories.
  ///
  /// The caller is responsible for deleting any keychain items via `deleteKeychainItemsForService`.
  /// The default profile cannot be deleted.
  public static func delete(
    name: String,
    applicationSupportRoot: URL = URL.applicationSupportDirectory,
    cachesRoot: URL = URL.cachesDirectory,
    deleteKeychainItemsForService: (String) throws -> Void = { _ in }
  ) throws {
    guard name != fallbackName else {
      throw ProfileError.cannotDeleteDefaultProfile
    }
    let profile = try named(name, applicationSupportRoot: applicationSupportRoot, cachesRoot: cachesRoot)
    let fm = FileManager.default

    if fm.fileExists(atPath: profile.directory.path(percentEncoded: false)) {
      try fm.removeItem(at: profile.directory)
    }
    if fm.fileExists(atPath: profile.cacheRoot.path(percentEncoded: false)) {
      try fm.removeItem(at: profile.cacheRoot)
    }

    try deleteKeychainItemsForService(profile.keychainService)
  }

  // MARK: - Command-line parsing

  /// Inspects command-line arguments and the environment for profile-related options.
  ///
  /// Unknown flags are ignored so that Apple's `-NS...` launch arguments keep working.
  public static func selected(
    from arguments: [String] = CommandLine.arguments,
    env: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ProfileSelection {
    var index = 1
    var profileName: String?
    var deleteProfileName: String?
    var shouldListProfiles = false
    var shouldShowHelp = false

    while index < arguments.count {
      let arg = arguments[index]

      if arg == "--profile" {
        guard index + 1 < arguments.count else {
          throw ProfileError.missingProfileValue
        }
        profileName = arguments[index + 1]
        index += 2
      } else if arg.hasPrefix("--profile=") {
        profileName = String(arg.dropFirst("--profile=".count))
        index += 1
      } else if arg == "--delete-profile" {
        guard index + 1 < arguments.count else {
          throw ProfileError.missingDeleteProfileValue
        }
        deleteProfileName = arguments[index + 1]
        index += 2
      } else if arg.hasPrefix("--delete-profile=") {
        deleteProfileName = String(arg.dropFirst("--delete-profile=".count))
        index += 1
      } else if arg == "--list-profiles" {
        shouldListProfiles = true
        index += 1
      } else if arg == "--help" || arg == "-h" {
        shouldShowHelp = true
        index += 1
      } else {
        // Ignore unknown flags and positional arguments.
        index += 1
      }
    }

    if profileName == nil, let envProfile = env["MACTRIX_PROFILE"], !envProfile.isEmpty {
      profileName = envProfile
    }

    if shouldShowHelp {
      return .help
    } else if shouldListProfiles {
      return .listProfiles
    } else if let deleteProfileName {
      return .deleteProfile(deleteProfileName)
    } else if let profileName {
      return .profile(try named(profileName))
    } else {
      return .none
    }
  }

  /// Human-readable usage text for `--help`.
  public static var usage: String {
    """
    Usage: Mactrix [options]

    Options:
      --profile <name>           Launch with the named profile (created if missing).
      --list-profiles            List all known profiles and exit.
      --delete-profile <name>    Delete a named profile's data, cache, and keychain items.
      --help, -h                 Show this message and exit.

    Environment:
      MACTRIX_PROFILE=<name>     Equivalent to --profile <name>.

    Without --profile, Mactrix uses the main profile and today's legacy storage paths.
    """
  }
}

private struct ProfileInfo: Codable {
  let name: String
  let schemaVersion: Int
  let createdAt: String
}

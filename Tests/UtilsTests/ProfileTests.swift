import Foundation
import Testing
import Utils

struct ProfileTests {
  private let bundleID = Bundle.main.bundleIdentifier ?? "dk.qpqp.mactrix"

  private func makeTempRoots() throws -> (appSupport: URL, caches: URL) {
    let fm = FileManager.default
    let base = fm.temporaryDirectory
      .appending(component: "ProfileTests-\(UUID().uuidString)")
    let appSupport = base.appending(component: "Application Support")
    let caches = base.appending(component: "Caches")
    try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
    try fm.createDirectory(at: caches, withIntermediateDirectories: true)
    return (appSupport, caches)
  }

  // MARK: - Identity

  @Test
  func defaultProfileIsDefault() {
    let profile = Profile.default
    #expect(profile.name == "default")
    #expect(profile.isDefault)
    #expect(profile.keychainService == bundleID)
  }

  @Test
  func namedProfileIsNotDefault() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = try Profile.named("test-server", applicationSupportRoot: appSupport, cachesRoot: caches)
    #expect(profile.name == "test-server")
    #expect(!profile.isDefault)
    #expect(profile.keychainService == "\(bundleID).profile.test-server")
  }

  // MARK: - Name validation

  @Test
  func validNames() throws {
    let (appSupport, caches) = try makeTempRoots()
    for name in ["a", "A", "test-server", "test_server", "test.server", "test-server-2", "a1"] {
      let profile = try Profile.named(name, applicationSupportRoot: appSupport, cachesRoot: caches)
      #expect(profile.name == name)
    }
  }

  @Test
  func invalidNames() throws {
    let (appSupport, caches) = try makeTempRoots()
    let invalid = ["", ".", "..", "default", ".hidden", "a/b", "a\\b", "a b", "a@b", "a+b", String(repeating: "a", count: 65)]
    for name in invalid {
      #expect(throws: ProfileError.self) {
        try Profile.named(name, applicationSupportRoot: appSupport, cachesRoot: caches)
      }
    }
  }

  // MARK: - Path layout

  @Test
  func defaultProfileUsesLegacyPaths() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = Profile.defaultProfile(applicationSupportRoot: appSupport, cachesRoot: caches)
    let storeID = "abc-123"

    let expectedData = appSupport
      .appending(component: bundleID)
      .appending(component: storeID)
    let expectedCache = caches
      .appending(component: bundleID)
      .appending(component: storeID)

    #expect(profile.dataDirectory(storeID: storeID) == expectedData)
    #expect(profile.cacheDirectory(storeID: storeID) == expectedCache)
  }

  @Test
  func namedProfileUsesScopedPaths() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = try Profile.named("test-server", applicationSupportRoot: appSupport, cachesRoot: caches)
    let storeID = "abc-123"

    let expectedDirectory = appSupport
      .appending(component: bundleID)
      .appending(component: "profiles")
      .appending(component: "test-server")
    let expectedData = expectedDirectory
      .appending(component: "data")
      .appending(component: storeID)
    let expectedCache = caches
      .appending(component: bundleID)
      .appending(component: "profiles")
      .appending(component: "test-server")
      .appending(component: "cache")
      .appending(component: storeID)

    #expect(profile.directory == expectedDirectory)
    #expect(profile.dataDirectory(storeID: storeID) == expectedData)
    #expect(profile.cacheDirectory(storeID: storeID) == expectedCache)
  }

  // MARK: - ensureExists

  @Test
  func ensureExistsIsIdempotent() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = try Profile.named("test-server", applicationSupportRoot: appSupport, cachesRoot: caches)

    try profile.ensureExists()
    try profile.ensureExists()

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: profile.directory.path(percentEncoded: false)))

    let profileJSON = profile.directory.appending(component: "profile.json")
    #expect(fm.fileExists(atPath: profileJSON.path(percentEncoded: false)))
  }

  @Test
  func ensureExistsDoesNotCreateProfilesFolderForDefault() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = Profile.defaultProfile(applicationSupportRoot: appSupport, cachesRoot: caches)
    try profile.ensureExists()

    let legacyRoot = appSupport.appending(component: bundleID)
    #expect(!FileManager.default.fileExists(atPath: legacyRoot.path(percentEncoded: false)))
  }

  // MARK: - list

  @Test
  func listIncludesDefaultAndNamedProfiles() throws {
    let (appSupport, caches) = try makeTempRoots()
    let alpha = try Profile.named("alpha", applicationSupportRoot: appSupport, cachesRoot: caches)
    let beta = try Profile.named("beta", applicationSupportRoot: appSupport, cachesRoot: caches)
    try alpha.ensureExists()
    try beta.ensureExists()

    let profiles = try Profile.list(applicationSupportRoot: appSupport, cachesRoot: caches)
    #expect(profiles.count == 3)
    #expect(profiles.contains(Profile.default))
    #expect(profiles.contains(alpha))
    #expect(profiles.contains(beta))
  }

  // MARK: - delete

  @Test
  func deleteRemovesDirectoriesAndCallsKeychainDeleter() throws {
    let (appSupport, caches) = try makeTempRoots()
    let profile = try Profile.named("test-server", applicationSupportRoot: appSupport, cachesRoot: caches)
    try profile.ensureExists()

    // Manually create the cache root so deletion of it is observable.
    let cacheRoot = caches
      .appending(component: bundleID)
      .appending(component: "profiles")
      .appending(component: "test-server")
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

    var deletedService: String?
    try Profile.delete(
      name: "test-server",
      applicationSupportRoot: appSupport,
      cachesRoot: caches
    ) { service in
      deletedService = service
    }

    #expect(deletedService == profile.keychainService)
    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: profile.directory.path(percentEncoded: false)))
    #expect(!fm.fileExists(atPath: cacheRoot.path(percentEncoded: false)))
  }

  @Test
  func deleteDefaultProfileThrows() throws {
    let (appSupport, caches) = try makeTempRoots()
    #expect(throws: ProfileError.cannotDeleteDefaultProfile) {
      try Profile.delete(
        name: "default",
        applicationSupportRoot: appSupport,
        cachesRoot: caches
      )
    }
  }

  // MARK: - CLI parsing

  @Test
  func parsesProfileFlag() throws {
    let selection = try Profile.selected(from: ["Mactrix", "--profile", "test-server"])
    if case .profile(let profile) = selection {
      #expect(profile.name == "test-server")
    } else {
      Issue.record("Expected .profile, got \(selection)")
    }
  }

  @Test
  func parsesProfileFlagWithEquals() throws {
    let selection = try Profile.selected(from: ["Mactrix", "--profile=test-server"])
    if case .profile(let profile) = selection {
      #expect(profile.name == "test-server")
    } else {
      Issue.record("Expected .profile, got \(selection)")
    }
  }

  @Test
  func profileFlagTakesPrecedenceOverEnv() throws {
    let selection = try Profile.selected(
      from: ["Mactrix", "--profile", "from-flag"],
      env: ["MACTRIX_PROFILE": "from-env"]
    )
    if case .profile(let profile) = selection {
      #expect(profile.name == "from-flag")
    } else {
      Issue.record("Expected .profile, got \(selection)")
    }
  }

  @Test
  func envProfileIsUsedWhenNoFlag() throws {
    let selection = try Profile.selected(
      from: ["Mactrix"],
      env: ["MACTRIX_PROFILE": "from-env"]
    )
    if case .profile(let profile) = selection {
      #expect(profile.name == "from-env")
    } else {
      Issue.record("Expected .profile, got \(selection)")
    }
  }

  @Test
  func parsesListProfilesFlag() throws {
    let selection = try Profile.selected(from: ["Mactrix", "--list-profiles"])
    #expect(selection == .listProfiles)
  }

  @Test
  func parsesDeleteProfileFlag() throws {
    let selection = try Profile.selected(from: ["Mactrix", "--delete-profile", "test-server"])
    #expect(selection == .deleteProfile("test-server"))
  }

  @Test
  func parsesHelpFlags() throws {
    #expect(try Profile.selected(from: ["Mactrix", "--help"]) == .help)
    #expect(try Profile.selected(from: ["Mactrix", "-h"]) == .help)
  }

  @Test
  func ignoresUnknownFlags() throws {
    let selection = try Profile.selected(from: ["Mactrix", "-NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints", "YES"])
    #expect(selection == .none)
  }

  @Test
  func rejectsInvalidProfileFlag() {
    #expect(throws: ProfileError.self) {
      try Profile.selected(from: ["Mactrix", "--profile", "../x"])
    }
  }

  @Test
  func rejectsDefaultProfileFlag() {
    #expect(throws: ProfileError.self) {
      try Profile.selected(from: ["Mactrix", "--profile", "default"])
    }
  }

  @Test
  func missingProfileValueThrows() {
    #expect(throws: ProfileError.missingProfileValue) {
      try Profile.selected(from: ["Mactrix", "--profile"])
    }
  }

  @Test
  func missingDeleteProfileValueThrows() {
    #expect(throws: ProfileError.missingDeleteProfileValue) {
      try Profile.selected(from: ["Mactrix", "--delete-profile"])
    }
  }

  @Test
  func usageIsNonEmpty() {
    #expect(!Profile.usage.isEmpty)
  }
}

import Testing

@testable import MactrixApp

struct AppVersionTests {
  @Test func ciBuild() {
    let version = AppVersion(info: [
      "CFBundleShortVersionString": "0.4.0",
      "CFBundleVersion": "123.2",
      "MactrixGitCommit": "b913c0d123456789",
    ])
    #expect(version.displayVersion == "0.4.0 (b913c0d)")
    #expect(version.build == "123.2")
  }

  @Test func localBuild() {
    let version = AppVersion(info: [
      "CFBundleShortVersionString": "0.0.0",
      "CFBundleVersion": "1",
      "MactrixGitCommit": "local",
    ])
    #expect(version.displayVersion == "0.0.0 (local)")
    #expect(version.build == "1")
  }

  @Test func missingMetadata() {
    #expect(AppVersion(info: [:]).displayVersion == "Development")
    #expect(AppVersion(info: [:]).build.isEmpty)
    #expect(AppVersion(info: ["CFBundleShortVersionString": "0.4.0"]).displayVersion == "0.4.0")
    #expect(
      AppVersion(info: ["MactrixGitCommit": "$(MACTRIX_GIT_COMMIT)"]).displayVersion
        == "Development")
  }
}

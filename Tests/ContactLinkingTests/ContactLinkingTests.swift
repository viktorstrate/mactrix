import Contacts
import Foundation
import Testing

@testable import ContactLinking

struct MatrixSocialProfileTests {
  @Test func parsesServiceAndUsername() {
    #expect(
      MatrixSocialProfile.userID(service: "Matrix", username: "@alice:example.org", urlString: nil)
        == "@alice:example.org")
  }

  @Test func serviceIsCaseInsensitive() {
    #expect(
      MatrixSocialProfile.userID(
        service: " matrix ", username: "@alice:example.org", urlString: nil)
        == "@alice:example.org")
  }

  @Test func addsMissingSigilAndLowercasesServer() {
    #expect(
      MatrixSocialProfile.userID(service: "Matrix", username: "Alice:Example.ORG", urlString: nil)
        == "@Alice:example.org")
  }

  @Test func parsesMatrixToURL() {
    #expect(
      MatrixSocialProfile.userID(
        service: "Other", username: nil, urlString: "https://matrix.to/#/%40alice%3Aexample.org")
        == "@alice:example.org")
  }

  @Test func parsesMatrixURI() {
    #expect(
      MatrixSocialProfile.userID(
        service: nil, username: nil, urlString: "matrix:u/alice:example.org?action=chat")
        == "@alice:example.org")
  }

  @Test func rejectsNonUserMatrixToLinks() {
    #expect(
      MatrixSocialProfile.userID(
        service: nil, username: nil, urlString: "https://matrix.to/#/#room:example.org") == nil)
  }

  @Test func rejectsOtherServicesAndJunk() {
    #expect(
      MatrixSocialProfile.userID(service: "Twitter", username: "@alice", urlString: nil) == nil)
    #expect(
      MatrixSocialProfile.userID(service: "Matrix", username: "not a user id", urlString: nil)
        == nil)
    #expect(
      MatrixSocialProfile.userID(service: "Matrix", username: "@:server", urlString: nil) == nil)
  }

  @Test func makeProfileRoundTrips() {
    let profile = MatrixSocialProfile.makeProfile(userID: "@alice:Example.org")
    #expect(profile.service == "Matrix")
    #expect(profile.username == "@alice:example.org")
    #expect(profile.urlString == "https://matrix.to/#/@alice:example.org")
    #expect(MatrixSocialProfile.userID(from: profile) == "@alice:example.org")
  }
}

struct LinkedContactTests {
  @Test func prefersNicknameWhenRequested() {
    let contact = LinkedContact(
      identifier: "1", fullName: "Alice Smith", nickname: "Ali", thumbnailData: nil)
    #expect(contact.displayName(preferNickname: true) == "Ali")
    #expect(contact.displayName(preferNickname: false) == "Alice Smith")
  }

  @Test func fallsBackWhenNamesAreMissing() {
    let nicknameOnly = LinkedContact(
      identifier: "1", fullName: "  ", nickname: "Ali", thumbnailData: nil)
    #expect(nicknameOnly.displayName(preferNickname: false) == "Ali")

    let fullNameOnly = LinkedContact(
      identifier: "2", fullName: "Alice Smith", nickname: "", thumbnailData: nil)
    #expect(fullNameOnly.displayName(preferNickname: true) == "Alice Smith")

    let empty = LinkedContact(identifier: "3", fullName: nil, nickname: nil, thumbnailData: nil)
    #expect(empty.displayName(preferNickname: true) == nil)
  }
}

@MainActor
struct ContactDirectoryTests {
  private let alice = LinkedContact(
    identifier: "1", fullName: "Alice Smith", nickname: "Ali", thumbnailData: nil)

  private func makeDirectory(enabled: Bool = true) -> ContactDirectory {
    let suite = "ContactDirectoryTests-\(UUID().uuidString)"
    // swift-format-ignore: NeverForceUnwrap
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set(enabled, forKey: ContactDirectory.DefaultsKey.isEnabled)
    return ContactDirectory(defaults: defaults, links: ["@alice:example.org": alice])
  }

  @Test func resolvesContactName() {
    let directory = makeDirectory()
    #expect(directory.resolvedName(userID: "@alice:example.org", matrixName: "xX_alice") == "Ali")

    directory.preferNicknames = false
    #expect(
      directory.resolvedName(userID: "@alice:example.org", matrixName: "xX_alice") == "Alice Smith")
  }

  @Test func lookupNormalisesUserID() {
    let directory = makeDirectory()
    #expect(directory.contactName(for: "@alice:EXAMPLE.org") == "Ali")
  }

  @Test func fallsBackToMatrixNameThenUserID() {
    let directory = makeDirectory()
    #expect(directory.resolvedName(userID: "@bob:example.org", matrixName: "Bob") == "Bob")
    #expect(
      directory.resolvedName(userID: "@bob:example.org", matrixName: "") == "@bob:example.org")
    #expect(
      directory.resolvedName(userID: "@bob:example.org", matrixName: nil) == "@bob:example.org")
  }

  @Test func respectsSettings() {
    let disabled = makeDirectory(enabled: false)
    #expect(
      disabled.resolvedName(userID: "@alice:example.org", matrixName: "xX_alice") == "xX_alice")

    let namesOff = makeDirectory()
    namesOff.useContactNames = false
    #expect(
      namesOff.resolvedName(userID: "@alice:example.org", matrixName: "xX_alice") == "xX_alice")
    #expect(namesOff.linkedContact(for: "@alice:example.org") == alice)
  }

  @Test func settingsChangesBumpRevision() {
    let directory = makeDirectory()
    let before = directory.revision
    directory.useContactPhotos = false
    #expect(directory.revision != before)
  }

  @Test func matrixIdentityHelp() {
    let directory = makeDirectory()
    #expect(
      directory.matrixIdentityHelp(userID: "@alice:example.org", matrixName: "xX_alice")
        == "xX_alice (@alice:example.org)")
    #expect(directory.matrixIdentityHelp(userID: "@bob:example.org", matrixName: "Bob") == nil)
  }
}

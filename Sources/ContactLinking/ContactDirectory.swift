import AppKit
import Contacts
import OSLog
import Observation

/// Links Matrix users to system contacts and resolves their names and photos.
///
/// Links are stored in Contacts itself (see ``MatrixSocialProfile``). All lookups honour the
/// app-wide contact settings, so callers can use them unconditionally.
@MainActor @Observable
public final class ContactDirectory {
  public static let shared = ContactDirectory()

  enum DefaultsKey {
    static let isEnabled = "contacts.isEnabled"
    static let useContactNames = "contacts.useContactNames"
    static let preferNicknames = "contacts.preferNicknames"
    static let useContactPhotos = "contacts.useContactPhotos"
  }

  // MARK: Settings

  /// Master switch for showing linked contacts. Turning it on requests Contacts access.
  public var isEnabled: Bool {
    didSet {
      guard isEnabled != oldValue else { return }
      defaults.set(isEnabled, forKey: DefaultsKey.isEnabled)
      settingsChanged()
      if isEnabled {
        Task { await requestAccessAndReload() }
      }
    }
  }

  public var useContactNames: Bool {
    didSet {
      guard useContactNames != oldValue else { return }
      defaults.set(useContactNames, forKey: DefaultsKey.useContactNames)
      settingsChanged()
    }
  }

  public var preferNicknames: Bool {
    didSet {
      guard preferNicknames != oldValue else { return }
      defaults.set(preferNicknames, forKey: DefaultsKey.preferNicknames)
      settingsChanged()
    }
  }

  public var useContactPhotos: Bool {
    didSet {
      guard useContactPhotos != oldValue else { return }
      defaults.set(useContactPhotos, forKey: DefaultsKey.useContactPhotos)
      settingsChanged()
    }
  }

  // MARK: State

  public private(set) var authorizationStatus: CNAuthorizationStatus
  /// Linked contacts keyed by normalised Matrix user ID.
  public private(set) var linksByUserID: [String: LinkedContact]
  /// Incremented whenever anything that affects names or photos changes.
  ///
  /// AppKit views observe this single value to know when to redraw.
  public private(set) var revision = 0

  public var isAuthorized: Bool {
    authorizationStatus == .authorized
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let usesSystemContacts: Bool
  @ObservationIgnored private var imageCache: [String: NSImage] = [:]
  @ObservationIgnored private var reloadTask: Task<Void, Never>?
  @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?

  private init() {
    defaults = .standard
    usesSystemContacts = true
    linksByUserID = [:]
    authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    isEnabled = defaults.object(forKey: DefaultsKey.isEnabled) as? Bool ?? false
    useContactNames = defaults.object(forKey: DefaultsKey.useContactNames) as? Bool ?? true
    preferNicknames = defaults.object(forKey: DefaultsKey.preferNicknames) as? Bool ?? true
    useContactPhotos = defaults.object(forKey: DefaultsKey.useContactPhotos) as? Bool ?? true

    changeObserver = NotificationCenter.default.addObserver(
      forName: .CNContactStoreDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.scheduleReload()
      }
    }

    scheduleReload(delay: .zero)
  }

  /// Creates a directory backed by fixed links instead of the system contacts. For tests.
  init(defaults: UserDefaults, links: [String: LinkedContact]) {
    self.defaults = defaults
    usesSystemContacts = false
    linksByUserID = links
    authorizationStatus = .authorized
    isEnabled = defaults.object(forKey: DefaultsKey.isEnabled) as? Bool ?? false
    useContactNames = defaults.object(forKey: DefaultsKey.useContactNames) as? Bool ?? true
    preferNicknames = defaults.object(forKey: DefaultsKey.preferNicknames) as? Bool ?? true
    useContactPhotos = defaults.object(forKey: DefaultsKey.useContactPhotos) as? Bool ?? true
  }

  // MARK: Lookup

  /// The contact linked to `userID`, or `nil` if there is none or the feature is off.
  public func linkedContact(for userID: String) -> LinkedContact? {
    guard isEnabled else { return nil }
    if let contact = linksByUserID[userID] {
      return contact
    }
    return MatrixSocialProfile.normalize(userID).flatMap { linksByUserID[$0] }
  }

  /// The contact name to show for `userID`, or `nil` to fall back to the Matrix name.
  public func contactName(for userID: String) -> String? {
    guard useContactNames else { return nil }
    return linkedContact(for: userID)?.displayName(preferNickname: preferNicknames)
  }

  /// The contact photo to show for `userID`, or `nil` to fall back to the Matrix avatar.
  public func contactImage(for userID: String) -> NSImage? {
    guard useContactPhotos, let contact = linkedContact(for: userID),
      let data = contact.thumbnailData
    else { return nil }

    if let cached = imageCache[contact.identifier] {
      return cached
    }
    let image = NSImage(data: data)
    imageCache[contact.identifier] = image
    return image
  }

  /// The name to show for a Matrix user: the linked contact name, the Matrix display name or
  /// the user ID, in that order.
  public func resolvedName(userID: String, matrixName: String?) -> String {
    if let contactName = contactName(for: userID) {
      return contactName
    }
    if let matrixName, !matrixName.isEmpty {
      return matrixName
    }
    return userID
  }

  /// Tooltip text showing the Matrix identity behind a contact name, or `nil` if the user
  /// isn't shown with a contact name.
  public func matrixIdentityHelp(userID: String, matrixName: String?) -> String? {
    guard contactName(for: userID) != nil else { return nil }
    if let matrixName, !matrixName.isEmpty {
      return "\(matrixName) (\(userID))"
    }
    return userID
  }

  // MARK: Access

  public func refreshAuthorizationStatus() {
    guard usesSystemContacts else { return }
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status != authorizationStatus {
      authorizationStatus = status
      scheduleReload(delay: .zero)
    }
  }

  public func requestAccessAndReload() async {
    guard usesSystemContacts else { return }
    if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
      do {
        _ = try await CNContactStore().requestAccess(for: .contacts)
      } catch {
        Logger.contacts.error("Contacts access request failed: \(error)")
      }
    }
    authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    await reload()
  }

  // MARK: Linking

  /// Links `userID` to the contact with `contactIdentifier`, removing any other link for it.
  public func link(userID: String, toContactIdentifier contactIdentifier: String) async throws {
    guard let userID = MatrixSocialProfile.normalize(userID) else { return }
    try await Task.detached(priority: .userInitiated) {
      try ContactStoreAccess.link(userID: userID, contactIdentifier: contactIdentifier)
    }.value
    await reload()
  }

  /// Removes `userID` from every contact it is linked to.
  public func unlink(userID: String) async throws {
    guard let userID = MatrixSocialProfile.normalize(userID) else { return }
    try await Task.detached(priority: .userInitiated) {
      try ContactStoreAccess.unlink(userID: userID)
    }.value
    await reload()
  }

  /// All contacts, sorted for display, for the contact picker.
  public func allContacts() async throws -> [ContactSummary] {
    guard usesSystemContacts, isAuthorized else { return [] }
    return try await Task.detached(priority: .userInitiated) {
      try ContactStoreAccess.allContacts()
    }.value
  }

  /// Opens the contact linked to `userID` in Contacts.app.
  public func openInContacts(userID: String) {
    guard let contact = linkedContact(for: userID),
      let url = URL(string: "addressbook://\(contact.identifier)")
    else { return }
    NSWorkspace.shared.open(url)
  }

  /// Opens the Contacts privacy pane in System Settings.
  public func openPrivacySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")
    else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: Loading

  /// Reloads the links from the system contacts.
  public func reload() async {
    guard usesSystemContacts else { return }
    guard isEnabled, CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      return
    }

    do {
      let links = try await Task.detached(priority: .utility) {
        try ContactStoreAccess.fetchLinks()
      }.value
      guard links != linksByUserID else { return }
      linksByUserID = links
      imageCache.removeAll()
      revision &+= 1
    } catch {
      Logger.contacts.error("Failed to load linked contacts: \(error)")
    }
  }

  private func scheduleReload(delay: Duration = .milliseconds(250)) {
    reloadTask?.cancel()
    reloadTask = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard !Task.isCancelled else { return }
      await self?.reload()
    }
  }

  private func settingsChanged() {
    imageCache.removeAll()
    revision &+= 1
    if usesSystemContacts, isEnabled, linksByUserID.isEmpty {
      scheduleReload(delay: .zero)
    }
  }
}

/// Blocking Contacts store operations. Always called off the main actor.
private enum ContactStoreAccess {
  static func fetchLinks() throws -> [String: LinkedContact] {
    let store = CNContactStore()

    // First pass: find contacts with Matrix social profiles without loading photos.
    var userIDsByContact: [String: [String]] = [:]
    let scanRequest = CNContactFetchRequest(keysToFetch: [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactSocialProfilesKey as CNKeyDescriptor,
    ])
    scanRequest.unifyResults = true
    try store.enumerateContacts(with: scanRequest) { contact, _ in
      let userIDs = contact.socialProfiles.compactMap { MatrixSocialProfile.userID(from: $0.value) }
      if !userIDs.isEmpty {
        userIDsByContact[contact.identifier, default: []].append(contentsOf: userIDs)
      }
    }

    guard !userIDsByContact.isEmpty else { return [:] }

    // Second pass: load names and photos for linked contacts only.
    let detailKeys: [CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactNicknameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactThumbnailImageDataKey as CNKeyDescriptor,
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ]
    let contacts = try store.unifiedContacts(
      matching: CNContact.predicateForContacts(withIdentifiers: Array(userIDsByContact.keys)),
      keysToFetch: detailKeys
    )

    var links: [String: LinkedContact] = [:]
    for contact in contacts {
      let linked = LinkedContact(
        identifier: contact.identifier,
        fullName: fullName(of: contact),
        nickname: contact.nickname,
        thumbnailData: contact.thumbnailImageData
      )
      for userID in userIDsByContact[contact.identifier] ?? [] {
        links[userID] = linked
      }
    }
    return links
  }

  static func allContacts() throws -> [ContactSummary] {
    let store = CNContactStore()
    let request = CNContactFetchRequest(keysToFetch: [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactNicknameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactThumbnailImageDataKey as CNKeyDescriptor,
      CNContactSocialProfilesKey as CNKeyDescriptor,
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ])
    request.unifyResults = true
    request.sortOrder = .userDefault

    var summaries: [ContactSummary] = []
    try store.enumerateContacts(with: request) { contact, _ in
      let nickname = contact.nickname.isEmpty ? nil : contact.nickname
      guard let name = fullName(of: contact) ?? nickname else { return }
      summaries.append(
        ContactSummary(
          identifier: contact.identifier,
          name: name,
          nickname: nickname,
          thumbnailData: contact.thumbnailImageData,
          linkedUserIDs: contact.socialProfiles.compactMap {
            MatrixSocialProfile.userID(from: $0.value)
          }
        ))
    }
    return summaries
  }

  static func link(userID: String, contactIdentifier: String) throws {
    let store = CNContactStore()
    let request = CNSaveRequest()
    var hasChanges = false

    for contact in try contactsLinked(to: userID, store: store)
    where contact.identifier != contactIdentifier {
      request.update(removingLink(to: userID, from: contact))
      hasChanges = true
    }

    let target = try store.unifiedContact(
      withIdentifier: contactIdentifier,
      keysToFetch: [CNContactSocialProfilesKey as CNKeyDescriptor])
    let isAlreadyLinked = target.socialProfiles.contains {
      MatrixSocialProfile.userID(from: $0.value) == userID
    }
    if !isAlreadyLinked, let mutable = target.mutableCopy() as? CNMutableContact {
      mutable.socialProfiles.append(
        CNLabeledValue(label: nil, value: MatrixSocialProfile.makeProfile(userID: userID)))
      request.update(mutable)
      hasChanges = true
    }

    if hasChanges {
      try store.execute(request)
    }
  }

  static func unlink(userID: String) throws {
    let store = CNContactStore()
    let request = CNSaveRequest()
    let contacts = try contactsLinked(to: userID, store: store)
    guard !contacts.isEmpty else { return }
    for contact in contacts {
      request.update(removingLink(to: userID, from: contact))
    }
    try store.execute(request)
  }

  private static func contactsLinked(to userID: String, store: CNContactStore) throws
    -> [CNContact]
  {
    var result: [CNContact] = []
    let request = CNContactFetchRequest(keysToFetch: [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactSocialProfilesKey as CNKeyDescriptor,
    ])
    request.unifyResults = true
    try store.enumerateContacts(with: request) { contact, _ in
      if contact.socialProfiles.contains(where: {
        MatrixSocialProfile.userID(from: $0.value) == userID
      }) {
        result.append(contact)
      }
    }
    return result
  }

  private static func removingLink(to userID: String, from contact: CNContact) -> CNMutableContact {
    // CNContact.mutableCopy() always returns a CNMutableContact.
    // swift-format-ignore: NeverForceUnwrap
    let mutable = contact.mutableCopy() as! CNMutableContact
    mutable.socialProfiles.removeAll {
      MatrixSocialProfile.userID(from: $0.value) == userID
    }
    return mutable
  }

  private static func fullName(of contact: CNContact) -> String? {
    if let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty {
      return name
    }
    return contact.organizationName.isEmpty ? nil : contact.organizationName
  }
}

extension Logger {
  static let contacts = Logger(subsystem: "dk.qpqp.mactrix.contact-linking", category: "contacts")
}

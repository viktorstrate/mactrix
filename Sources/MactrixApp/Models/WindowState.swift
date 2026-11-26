import Foundation
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

public enum InspectorContent: Equatable {
  case roomInfo
  case search
  case userInfo(userId: String)
  case roomThreads
  case roomPins
  case focusThread(threadTimeline: LiveTimeline)
}

public enum SearchDirectResult {
  case lookingForRoom(alias: String)
  case roomNotFound(alias: String)
  case resolvedRoomAlias(alias: String, resolvedRoom: MatrixRustSDK.ResolvedRoomAlias)
  case resolvedRoomId(roomPreview: MatrixRustSDK.RoomPreview)
  case lookingForUser(userId: String)
  case userNotFound(userId: String)
  case resolvedUser(profile: MatrixRustSDK.UserProfile)
}

/// A destination's identity distinguishes separate visits, even to the same room or URL.
@MainActor
public final class SelectedScreen: Identifiable {
  public enum Content {
    case loadingRoom(String)
    case joinedRoom(timeline: LiveTimeline)
    case loadMatrixUrl(Utils.MatrixUriScheme)
    case previewRoom(RoomPreview, eventId: String?, routingVia: [String])
    case user(profile: UserProfile)
    case newRoom
    case none
  }

  public let content: Content
  public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

  private init(_ content: Content) {
    self.content = content
  }

  public static func loadingRoom(_ roomId: String) -> SelectedScreen {
    SelectedScreen(.loadingRoom(roomId))
  }

  public static func joinedRoom(timeline: LiveTimeline) -> SelectedScreen {
    SelectedScreen(.joinedRoom(timeline: timeline))
  }

  public static func loadMatrixUrl(_ url: Utils.MatrixUriScheme) -> SelectedScreen {
    SelectedScreen(.loadMatrixUrl(url))
  }

  public static func previewRoom(
    _ room: RoomPreview, eventId: String? = nil, routingVia: [String] = []
  ) -> SelectedScreen {
    SelectedScreen(.previewRoom(room, eventId: eventId, routingVia: routingVia))
  }

  public static func user(profile: UserProfile) -> SelectedScreen {
    SelectedScreen(.user(profile: profile))
  }

  public static var newRoom: SelectedScreen { SelectedScreen(.newRoom) }
  public static var none: SelectedScreen { SelectedScreen(.none) }
}

/// Why the sign-in sheet is shown.
public enum LoginSheet: Identifiable, Equatable {
  /// No account is signed in.
  case firstAccount
  case addAccount
  /// The server ended this account's session.
  case signInAgain(userID: String)

  public var id: String {
    switch self {
    case .firstAccount: "first"
    case .addAccount: "add"
    case .signInAgain(let userID): "again:\(userID)"
    }
  }
}

@MainActor @Observable
public final class WindowState {
  public var selectedScreen: SelectedScreen = .none {
    didSet {
      if case .joinedRoom(let previous) = oldValue.content,
        case .joinedRoom(let current) = selectedScreen.content, previous === current
      {
        return
      }
      conversationSelection = nil
    }
  }

  @ObservationIgnored let quickNavigation = QuickNavigationCoordinator()

  var conversationSelection: ConversationMessageSelection?

  /// The account whose rooms `selectedRoomId` and `selectedSpaceId` refer to.
  public private(set) var accountID: String?

  /// The client of the account this window shows. `AppState` owns the clients.
  public private(set) weak var matrixClient: MatrixClient?

  /// The window showing this state.
  @ObservationIgnored weak var window: NSWindow?

  /// Brings this window to the front, selecting its tab and restoring it from the Dock.
  func bringToFront() {
    guard let window else { return }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.tabGroup?.selectedWindow = window
    window.makeKeyAndOrderFront(nil)
  }

  public var selectedRoomId: String? {
    get {
      switch selectedScreen.content {
      case .loadingRoom(let roomId): roomId
      case .joinedRoom(let timeline): timeline.room.id
      case .previewRoom(let room, _, _): room.info().roomId
      case .loadMatrixUrl(let url):
        if case .roomId(let id) = url.kind { id } else { nil }
      case .user, .newRoom, .none: nil
      }
    }
    set { selectRoom(newValue) }
  }

  public func selectRoom(_ roomId: String?) {
    guard roomId != selectedRoomId else { return }
    selectedScreen = roomId.map(SelectedScreen.loadingRoom) ?? .none
  }

  /// Select an event reusing the current timline if available, or loads it in a new one.
  public func selectEvent(roomId: String, eventId: String) {
    // if existing timeline contains the event, focus it without reloading.
    let target = EventOrTransactionId.eventId(eventId: eventId)
    if case .joinedRoom(timeline: let timeline) = selectedScreen.content,
      timeline.room.id == roomId
        && timeline.timelineItems.contains(where: { $0.asEvent()?.eventOrTransactionId == target })
    {
      timeline.focusEvent(id: target)
      return
    }

    selectedScreen = SelectedScreen.loadMatrixUrl(.init(kind: .roomId(roomId), event: eventId))
  }

  public var selectedSpaceId: String?
  /// The last selection of accounts other than `accountID`, restored when switching back.
  var accountSelections: [String: AccountSelection] = [:]
  public var inspectorVisible: Bool = false

  public var inspectorContent: InspectorContent = .roomInfo

  public var requestedVerification = false

  public var loginSheet: LoginSheet?

  public var searchQuery: String = ""
  public var searchTokens: [SearchToken] = []
  public var searchDirectResult: SearchDirectResult?

  /// The collapsed/expanded states of the sections in the sidebar.
  public var sidebarSections = SidebarSectionCollapsibility()

  public var searchFocused: Binding<Bool> {
    Binding(
      get: { self.inspectorContent == .search },
      set: { setFocused in
        if setFocused {
          self.inspectorContent = .search
          self.inspectorVisible = true
        }

        if !setFocused, self.inspectorContent == .search {
          self.inspectorContent = .roomInfo
        }
      }
    )
  }

  /// Shows `account`, remembering the current account's selection and restoring the new one's.
  public func showAccount(_ account: MatrixClient?, knownAccountIDs: Set<String>) {
    showAccount(account?.storeID, knownAccountIDs: knownAccountIDs)
    matrixClient = account
  }

  /// Shows `newAccountID`, remembering the current account's selection and restoring the new one's.
  ///
  /// `knownAccountIDs` lists the accounts that still exist; selections of others are dropped.
  public func showAccount(_ newAccountID: String?, knownAccountIDs: Set<String>) {
    accountSelections = accountSelections.filter { knownAccountIDs.contains($0.key) }
    guard newAccountID != accountID else { return }

    // State saved before multi-account support has no account; it belongs to the first one shown.
    if accountID == nil, newAccountID != nil, accountSelections.isEmpty {
      accountID = newAccountID
      return
    }

    if let accountID, knownAccountIDs.contains(accountID) {
      accountSelections[accountID] = AccountSelection(
        roomId: selectedRoomId, spaceId: selectedSpaceId)
    }
    let restored = newAccountID.flatMap { accountSelections.removeValue(forKey: $0) }
    accountID = newAccountID
    selectedScreen = .none
    selectedRoomId = restored?.roomId
    selectedSpaceId = restored?.spaceId
    inspectorContent = .roomInfo
    searchQuery = ""
    searchTokens = []
    searchDirectResult = nil
    requestedVerification = false
  }

  public func toggleInspector() {
    if inspectorVisible {
      if inspectorContent == .roomInfo {
        inspectorVisible = false
      } else {
        inspectorContent = .roomInfo
      }
    } else {
      inspectorVisible = true
      inspectorContent = .roomInfo
    }
  }

  public func focusEventInCurrentTimeline(eventId: String) {
    guard case .joinedRoom(timeline: let roomTimeline) = selectedScreen.content else {
      Logger.windowState.warning("focus message failed, no active timeline")
      return
    }

    roomTimeline.focusEvent(id: .eventId(eventId: eventId))
  }

  /// Focus the event in the `sourceTimeline` if it is loaded,
  /// otherwise load a new timeline focused at the given event.
  func focusReply(eventId: String, from sourceTimeline: LiveTimeline) {
    guard case .joinedRoom(let roomTimeline) = selectedScreen.content,
      roomTimeline.room.id == sourceTimeline.room.id
    else { return }

    let target = EventOrTransactionId.eventId(eventId: eventId)
    if roomTimeline.timelineItems.contains(where: { $0.asEvent()?.eventOrTransactionId == target })
    {
      roomTimeline.focusEvent(id: target)
    } else {
      selectedScreen = .joinedRoom(
        timeline: LiveTimeline(room: roomTimeline.room, focus: .event(eventId: eventId)))
    }
  }

  /// Return a historical timeline to a live one.
  func returnToLive(from history: LiveTimeline) {
    guard case .joinedRoom(let current) = selectedScreen.content, current === history else {
      return
    }
    selectedScreen = .joinedRoom(timeline: LiveTimeline(room: history.room))
    Logger.windowState.debug("Return to live timeline")
  }

  public func focusThread(rootEventId: String) {
    guard case .joinedRoom(timeline: let roomTimeline) = selectedScreen.content else { return }

    inspectorVisible = true
    inspectorContent = .focusThread(
      threadTimeline: LiveTimeline(room: roomTimeline.room, focusThread: rootEventId))
  }

  public func showRoomThreads() {
    if inspectorVisible, inspectorContent == .roomThreads {
      inspectorVisible = false
    } else {
      inspectorContent = .roomThreads
      inspectorVisible = true
    }
  }

  public func showRoomPins() {
    if inspectorVisible, inspectorContent == .roomPins {
      inspectorVisible = false
    } else {
      inspectorContent = .roomPins
      inspectorVisible = true
    }
  }

  public func focusUser(userId: String) {
    if inspectorVisible, inspectorContent == .userInfo(userId: userId) {
      inspectorVisible = false
    } else {
      inspectorContent = .userInfo(userId: userId)
      inspectorVisible = true
    }
  }
}

struct AccountSelection: Codable, Equatable {
  var roomId: String?
  var spaceId: String?
}

extension WindowState: @MainActor RawRepresentable {
  public struct SceneStorageRepresentation: Codable {
    let selectedRoomId: String?
    let selectedSpaceId: String?
    let inspectorVisible: Bool
    let sidebarSections: SidebarSectionCollapsibility
    // Absent in state saved before multi-account support.
    let accountID: String?
    let accountSelections: [String: AccountSelection]?

    @MainActor init(windowState: WindowState) {
      self.selectedRoomId = windowState.selectedRoomId
      self.selectedSpaceId = windowState.selectedSpaceId
      self.inspectorVisible = windowState.inspectorVisible
      self.sidebarSections = windowState.sidebarSections
      self.accountID = windowState.accountID
      self.accountSelections = windowState.accountSelections
    }

    @MainActor func restore(windowState: WindowState) {
      windowState.selectedRoomId = selectedRoomId
      windowState.selectedSpaceId = selectedSpaceId
      windowState.inspectorVisible = inspectorVisible
      windowState.sidebarSections = sidebarSections
      windowState.accountID = accountID
      windowState.accountSelections = accountSelections ?? [:]
    }
  }

  public convenience init?(rawValue: String) {
    guard
      let data = rawValue.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(SceneStorageRepresentation.self, from: data)
    else {
      Logger.windowState.warning("Failed to recover WindowState from storage: \(rawValue)")
      return nil
    }

    self.init()
    decoded.restore(windowState: self)
    Logger.windowState.info("WindowState recovered from storage: \(rawValue)")
  }

  public var rawValue: String {
    guard
      let data = try? JSONEncoder().encode(SceneStorageRepresentation(windowState: self)),
      let result = String(data: data, encoding: .utf8)
    else {
      return ""
    }

    return result
  }

  public typealias RawValue = String
}

public enum SearchToken: Hashable, Identifiable {
  case users, rooms, spaces, messages
  case resolvedRoomAlias(alias: String, resolvedRoom: ResolvedRoomAlias)
  case resolvedRoomId(roomPreview: RoomPreview)
  case resolvedUser(profile: UserProfile)

  public var id: Self {
    self
  }
}

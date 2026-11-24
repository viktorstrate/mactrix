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
  public var selectedSpaceId: String?
  public var inspectorVisible: Bool = false

  public var inspectorContent: InspectorContent = .roomInfo

  public var requestedVerification = false

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

  public func focusMessage(eventId: String) {
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

extension WindowState: @MainActor RawRepresentable {
  public struct SceneStorageRepresentation: Codable {
    let selectedRoomId: String?
    let selectedSpaceId: String?
    let inspectorVisible: Bool
    let sidebarSections: SidebarSectionCollapsibility

    @MainActor init(windowState: WindowState) {
      self.selectedRoomId = windowState.selectedRoomId
      self.selectedSpaceId = windowState.selectedSpaceId
      self.inspectorVisible = windowState.inspectorVisible
      self.sidebarSections = windowState.sidebarSections
    }

    @MainActor func restore(windowState: WindowState) {
      windowState.selectedRoomId = selectedRoomId
      windowState.selectedSpaceId = selectedSpaceId
      windowState.inspectorVisible = inspectorVisible
      windowState.sidebarSections = sidebarSections
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

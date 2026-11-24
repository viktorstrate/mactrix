import Testing
import Utils

@testable import MactrixApp

@MainActor
struct WindowStateNavigationTests {
  @Test func selectingRoomCreatesLoadingDestination() {
    let state = WindowState()
    state.selectRoom("!room:example.org")

    guard case .loadingRoom(let roomId) = state.selectedScreen.content else {
      Issue.record("Expected a room-loading destination")
      return
    }
    #expect(roomId == "!room:example.org")
    #expect(state.selectedRoomId == roomId)
  }

  @Test func selectingCurrentRoomDoesNotRestartNavigation() {
    let state = WindowState()
    state.selectRoom("!room:example.org")
    let screen = state.selectedScreen

    state.selectedRoomId = "!room:example.org"

    #expect(state.selectedScreen === screen)
  }

  @Test func nonRoomDestinationsClearSidebarSelection() throws {
    let state = WindowState()
    state.selectRoom("!room:example.org")
    state.selectedScreen = .newRoom
    #expect(state.selectedRoomId == nil)

    state.selectRoom("!room:example.org")
    state.selectedScreen = .loadMatrixUrl(
      try MatrixUriScheme(parseUrl: "matrix:u/alice:example.org"))
    #expect(state.selectedRoomId == nil)
  }

  @Test func roomLinkSelectionComesFromItsDestination() throws {
    let state = WindowState()
    state.selectedScreen = .loadMatrixUrl(
      try MatrixUriScheme(parseUrl: "matrix:roomid/room:example.org/e/event"))

    #expect(state.selectedRoomId == "!room:example.org")

    state.selectRoom(nil)
    guard case .none = state.selectedScreen.content else {
      Issue.record("Expected deselection to clear the destination")
      return
    }
  }

  @Test func returningToSameRoomHasNewDestinationIdentity() {
    let state = WindowState()
    state.selectRoom("!a:example.org")
    let firstVisit = state.selectedScreen
    state.selectRoom("!b:example.org")
    state.selectRoom("!a:example.org")

    #expect(state.selectedRoomId == "!a:example.org")
    #expect(state.selectedScreen !== firstVisit)
    #expect(state.selectedScreen.id != firstVisit.id)
  }

  @Test func reopeningSameLinkHasNewDestinationIdentity() throws {
    let uri = try MatrixUriScheme(parseUrl: "matrix:r/room:example.org")
    let state = WindowState()
    state.selectedScreen = .loadMatrixUrl(uri)
    let firstVisit = state.selectedScreen
    state.selectedScreen = .loadMatrixUrl(uri)

    #expect(state.selectedScreen !== firstVisit)
  }

  @Test func sceneRestorationCreatesRoomLoadingDestination() throws {
    let state = WindowState()
    state.selectRoom("!room:example.org")
    let restored = try #require(WindowState(rawValue: state.rawValue))

    #expect(restored.selectedRoomId == "!room:example.org")
    guard case .loadingRoom = restored.selectedScreen.content else {
      Issue.record("Expected a restored room to load through normal navigation")
      return
    }
  }

  @Test func nonRoomScreenDoesNotRestorePreviousRoom() throws {
    let state = WindowState()
    state.selectRoom("!room:example.org")
    state.selectedScreen = .newRoom
    let restored = try #require(WindowState(rawValue: state.rawValue))

    #expect(restored.selectedRoomId == nil)
    guard case .none = restored.selectedScreen.content else {
      Issue.record("Expected no room to be restored")
      return
    }
  }
}

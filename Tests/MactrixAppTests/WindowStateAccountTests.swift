import Foundation
import Testing

@testable import MactrixApp

@MainActor
struct WindowStateAccountTests {
  @Test func stateSavedBeforeMultiAccountIsAdoptedByFirstAccount() throws {
    let legacy = """
      {"selectedRoomId":"!room:example.org","selectedSpaceId":"!space:example.org",\
      "inspectorVisible":true,"sidebarSections":\(try sidebarJSON())}
      """
    let windowState = try #require(WindowState(rawValue: legacy))
    #expect(windowState.accountID == nil)

    windowState.showAccount("A", knownAccountIDs: ["A"])

    #expect(windowState.accountID == "A")
    #expect(windowState.selectedRoomId == "!room:example.org")
    #expect(windowState.selectedSpaceId == "!space:example.org")
    #expect(windowState.inspectorVisible)
  }

  @Test func switchingRestoresEachAccountsSelection() {
    let windowState = WindowState()
    windowState.showAccount("A", knownAccountIDs: ["A", "B"])
    windowState.selectedRoomId = "!a:example.org"
    windowState.selectedSpaceId = "!a-space:example.org"

    windowState.showAccount("B", knownAccountIDs: ["A", "B"])
    #expect(windowState.selectedRoomId == nil)
    #expect(windowState.selectedSpaceId == nil)
    windowState.selectedRoomId = "!b:example.org"

    windowState.showAccount("A", knownAccountIDs: ["A", "B"])
    #expect(windowState.selectedRoomId == "!a:example.org")
    #expect(windowState.selectedSpaceId == "!a-space:example.org")

    windowState.showAccount("B", knownAccountIDs: ["A", "B"])
    #expect(windowState.selectedRoomId == "!b:example.org")
  }

  @Test func switchingResetsTransientState() {
    let windowState = WindowState()
    windowState.showAccount("A", knownAccountIDs: ["A", "B"])
    windowState.inspectorContent = .roomThreads
    windowState.searchQuery = "hello"
    windowState.searchTokens = [.rooms]

    windowState.showAccount("B", knownAccountIDs: ["A", "B"])

    #expect(windowState.inspectorContent == .roomInfo)
    #expect(windowState.searchQuery.isEmpty)
    #expect(windowState.searchTokens.isEmpty)
    if case .none = windowState.selectedScreen.content {} else { Issue.record("screen not reset") }
  }

  @Test func removedAccountsAreForgotten() {
    let windowState = WindowState()
    windowState.showAccount("A", knownAccountIDs: ["A", "B"])
    windowState.selectedRoomId = "!a:example.org"
    windowState.showAccount("B", knownAccountIDs: ["A", "B"])
    #expect(windowState.accountSelections.keys.contains("A"))

    // Account A is signed out while B is shown.
    windowState.showAccount("B", knownAccountIDs: ["B"])
    #expect(windowState.accountSelections.isEmpty)
  }

  @Test func signingOutOfLastAccountClearsSelection() {
    let windowState = WindowState()
    windowState.showAccount("A", knownAccountIDs: ["A"])
    windowState.selectedRoomId = "!a:example.org"

    windowState.showAccount(nil, knownAccountIDs: [])
    #expect(windowState.accountID == nil)
    #expect(windowState.selectedRoomId == nil)

    windowState.showAccount("C", knownAccountIDs: ["C"])
    #expect(windowState.accountID == "C")
    #expect(windowState.selectedRoomId == nil)
  }

  @Test func roundTripsThroughSceneStorage() throws {
    let windowState = WindowState()
    windowState.showAccount("A", knownAccountIDs: ["A", "B"])
    windowState.selectedRoomId = "!a:example.org"
    windowState.showAccount("B", knownAccountIDs: ["A", "B"])
    windowState.selectedRoomId = "!b:example.org"

    let restored = try #require(WindowState(rawValue: windowState.rawValue))
    #expect(restored.accountID == "B")
    #expect(restored.selectedRoomId == "!b:example.org")
    #expect(restored.accountSelections["A"] == AccountSelection(roomId: "!a:example.org"))
  }

  private func sidebarJSON() throws -> String {
    String(decoding: try JSONEncoder().encode(SidebarSectionCollapsibility()), as: UTF8.self)
  }
}

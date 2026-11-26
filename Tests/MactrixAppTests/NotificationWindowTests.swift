import Testing

@testable import MactrixApp

@MainActor
struct NotificationWindowTests {
  @Test func notificationOpensInWindowShowingItsAccount() {
    let frontmost = window(showing: "A")
    let background = window(showing: "B")
    let older = window(showing: "B")

    let chosen = AppState.window(forAccountID: "B", in: [frontmost, background, older])
    #expect(chosen === background)
  }

  @Test func notificationSwitchesFrontmostWindowWhenNoneShowsItsAccount() {
    let frontmost = window(showing: "A")
    let background = window(showing: "B")

    let chosen = AppState.window(forAccountID: "C", in: [frontmost, background])
    #expect(chosen === frontmost)
  }

  @Test func notificationWithoutAccountOpensInFrontmostWindow() {
    let frontmost = window(showing: nil)
    let background = window(showing: "B")

    let chosen = AppState.window(forAccountID: nil, in: [frontmost, background])
    #expect(chosen === frontmost)
  }

  @Test func notificationWaitsForAWindow() {
    #expect(AppState.window(forAccountID: "A", in: []) == nil)
  }

  private func window(showing accountID: String?) -> WindowState {
    let windowState = WindowState()
    windowState.showAccount(accountID, knownAccountIDs: Set([accountID].compactMap { $0 }))
    return windowState
  }
}

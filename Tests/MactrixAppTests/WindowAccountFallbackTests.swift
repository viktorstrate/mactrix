import Testing

@testable import MactrixApp

@MainActor
struct WindowAccountFallbackTests {
  @Test func windowKeepsItsOwnAccount() {
    let shown = AppState.accountToShow(
      windowAccountID: "B", lastFocusedAccountID: "A", accountIDs: ["A", "B"])
    #expect(shown == "B")
  }

  @Test func newWindowOpensOnLastFocusedAccount() {
    let shown = AppState.accountToShow(
      windowAccountID: nil, lastFocusedAccountID: "B", accountIDs: ["A", "B"])
    #expect(shown == "B")
  }

  @Test func removedAccountFallsBackToLastFocused() {
    let shown = AppState.accountToShow(
      windowAccountID: "C", lastFocusedAccountID: "B", accountIDs: ["A", "B"])
    #expect(shown == "B")
  }

  @Test func fallsBackToFirstAccountWhenLastFocusedIsGone() {
    let shown = AppState.accountToShow(
      windowAccountID: "C", lastFocusedAccountID: "D", accountIDs: ["A", "B"])
    #expect(shown == "A")
  }

  @Test func showsNothingWithoutAccounts() {
    let shown = AppState.accountToShow(
      windowAccountID: "A", lastFocusedAccountID: "A", accountIDs: [])
    #expect(shown == nil)
  }
}

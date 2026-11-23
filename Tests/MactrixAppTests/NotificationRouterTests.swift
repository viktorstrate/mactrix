import Testing

@testable import MatrixIntegration

@MainActor
struct NotificationRouterTests {
  @Test func showsInactiveAccountsWhileFrontmost() {
    let options = NotificationRouter.foregroundPresentation(
      forAccountID: "inactive", activeAccountID: "active")
    #expect(options == [.banner, .list, .sound])
  }

  @Test func keepsActiveAccountSilentWhileFrontmost() {
    let options = NotificationRouter.foregroundPresentation(
      forAccountID: "active", activeAccountID: "active")
    #expect(options.isEmpty)
  }

  @Test func keepsNotificationsWithoutAccountSilent() {
    let options = NotificationRouter.foregroundPresentation(
      forAccountID: nil, activeAccountID: "active")
    #expect(options.isEmpty)
  }
}

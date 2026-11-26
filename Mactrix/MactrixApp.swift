import MactrixApp
import MatrixIntegration
import OSLog
import SwiftUI

@main
struct MactrixApp: App {
  @State var appState = AppState()
  @FocusedValue(WindowState.self) private var windowState: WindowState?

  var body: some Scene {
    WindowGroup(id: "main") {
      MainView()
    }
    .windowToolbarStyle(.automatic)
    .environment(appState)
    .commands {
      AppCommands(appState: appState)
    }
    .onChange(of: windowState.map(ObjectIdentifier.init)) {
      if let windowState { appState.focus(windowState) }
      focusNotification()
    }
    .onChange(of: appState.notificationRouter.pendingTarget, focusNotification)
    .onChange(of: appState.restoration, focusNotification)

    Settings {
      SettingsView()
    }
    .environment(appState)
  }

  func focusNotification() {
    guard let windowState else { return }
    appState.showNotificationTarget(in: windowState)
  }
}

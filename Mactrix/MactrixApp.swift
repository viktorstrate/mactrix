import OSLog
import SwiftUI

let applicationID = "dk.qpqp.mactrix"

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
            AppCommands()
        }
        .onChange(of: windowState == nil, focusNotification)
        .onChange(of: appState.matrixClient?.notifications.selectedRoomId == nil, focusNotification)

        Settings {
            SettingsView()
        }
        .environment(appState)
    }

    func focusNotification() {
        guard let windowState else { return }
        guard let notificationRoomId = appState.matrixClient?.notifications.selectedRoomId else { return }

        windowState.selectedRoomId = notificationRoomId
        appState.matrixClient?.notifications.selectedRoomId = nil
    }
}

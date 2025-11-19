import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        TextEditingCommands()
        ToolbarCommands()

        newTab
    }

    var newTab: some Commands {
        CommandGroup(after: .newItem) {
            Button(action: {
                guard let currentMainWindow = NSApp.orderedWindows.first(where: { window in
                    window.identifier?.rawValue.starts(with: "main-AppWindow") ?? false
                }) else {
                    return
                }

                guard let windowController = currentMainWindow.windowController else {
                    return
                }

                windowController.newWindowForTab(nil)
                if let newWindow = NSApp.keyWindow, currentMainWindow != newWindow {
                    currentMainWindow.addTabbedWindow(newWindow, ordered: .above)
                    newWindow.makeKeyAndOrderFront(nil)
                }
            }) {
                Text("New Tab")
            }
            .keyboardShortcut("t", modifiers: [.command])

            if let windowState {
                Self.createRoomButton(windowState: windowState)
            }
        }
    }

    static func createRoomButton(windowState: WindowState) -> some View {
        Button {
            windowState.selectedScreen = .newRoom
        } label: {
            Label("Create room", systemImage: "plus.bubble")
        }
        .help("Create a new room")
        .keyboardShortcut("N", modifiers: [.command, .shift])
    }
}

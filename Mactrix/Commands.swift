import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    @FocusedValue(AppState.self) private var appState: AppState?

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        TextEditingCommands()
        ToolbarCommands()

        newTab
        roomNavigation
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
    
    var roomNavigation: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Previous Room") {
                guard let windowState, let appState else { return }
                let roomIds = appState.matrixClient?.orderedRoomIds ?? []
                windowState.selectPreviousRoom(rooms: roomIds)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(windowState == nil || appState == nil)
            
            Button("Next Room") {
                guard let windowState, let appState else { return }
                let roomIds = appState.matrixClient?.orderedRoomIds ?? []
                windowState.selectNextRoom(rooms: roomIds)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(windowState == nil || appState == nil)
        }
    }
}

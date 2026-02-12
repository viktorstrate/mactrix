import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    @AppStorage("fontSize") var fontSize: Int = 13

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        TextEditingCommands()
        ToolbarCommands()

        newTab
        fontSizeCommands
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
    
    var fontSizeCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button {
                fontSize += 1
            } label: {
                Text("Make Text Bigger")
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(fontSize >= 24)

            Button {
                fontSize = 13
            } label: {
                Text("Make Text Normal Size")
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(fontSize == 13)

            Button {
                fontSize -= 1
                    
            } label: {
                Text("Make Text Smaller")
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(fontSize <= 8)
        }
    }
}

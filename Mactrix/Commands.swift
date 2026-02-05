import SwiftUI
import MatrixRustSDK

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
                let roomIds = getRoomIds(appState: appState)
                windowState.selectPreviousRoom(rooms: roomIds)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(windowState == nil || appState == nil)
            
            Button("Next Room") {
                guard let windowState, let appState else { return }
                let roomIds = getRoomIds(appState: appState)
                windowState.selectNextRoom(rooms: roomIds)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(windowState == nil || appState == nil)
        }
    }
    
    private func getRoomIds(appState: AppState) -> [String] {
        guard let matrixClient = appState.matrixClient else { return [] }
        
        let favorites = matrixClient.rooms.filter { $0.roomInfo?.isFavourite == true }
        let directs = matrixClient.rooms.filter { room in
            let isDirect = room.roomInfo?.isDirect == true
            let favoriteIDs = Set(favorites.map { $0.id })
            return isDirect && !favoriteIDs.contains(room.id)
        }
        let rooms = matrixClient.rooms.filter { room in
            let isSpace = room.room.isSpace()
            let isDirect = room.roomInfo?.isDirect == true
            let favoriteIDs = Set(favorites.map(\.id))
            return !isSpace && !isDirect && !favoriteIDs.contains(room.id)
        }
        let spaces = matrixClient.spaceService.spaceRooms
        
        var allRoomIds: [String] = []
        allRoomIds.append(contentsOf: favorites.map { $0.id })
        allRoomIds.append(contentsOf: directs.map { $0.id })
        allRoomIds.append(contentsOf: rooms.map { $0.id })
        
        // Add space rooms
        for space in spaces {
            allRoomIds.append(space.id)
            // Add child rooms if they're loaded
            if case let .loaded(children) = space.children {
                allRoomIds.append(contentsOf: children.rooms.map { $0.id })
            }
        }
        
        return allRoomIds
    }
}

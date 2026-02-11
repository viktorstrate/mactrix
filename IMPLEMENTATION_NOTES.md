# Implementation Summary: Automatic Input Focus and Room Navigation

## Overview
Implemented automatic focus for the message input field when opening or navigating between rooms, plus keyboard shortcuts (Command+Shift+[ and Command+Shift+]) for room navigation while maintaining input focus.

---

## Changes Made

### 1. **ChatInputView.swift** - Made focus state controllable from parent

**Original:**
```swift
struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @Binding var height: CGFloat?

    @State private var chatInput: String = ""
    @FocusState private var chatFocused: Bool

    // TextField
    TextField("Message room", text: $chatInput, axis: .vertical)
        .focused($chatFocused)

    // Tap gesture
    .onTapGesture {
        chatFocused = true
    }
}
```

**Final:**
```swift
struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @Binding var height: CGFloat?
    var focusState: FocusState<Bool>.Binding  // NEW: Accept external focus state

    @State private var chatInput: String = ""
    // REMOVED: @FocusState private var chatFocused: Bool

    // TextField
    TextField("Message room", text: $chatInput, axis: .vertical)
        .focused(focusState)  // CHANGED: Use external focus state

    // Tap gesture
    .onTapGesture {
        focusState.wrappedValue = true  // CHANGED: Use external focus state
    }
}
```

---

### 2. **ChatView.swift** - Added focus management and trigger handling

**Original:**
```swift
struct ChatJoinedRoom: View {
    @Environment(AppState.self) private var appState
    @Bindable var timeline: LiveTimeline

    var room: LiveRoom {
        timeline.room
    }

    @State private var inputHeight: CGFloat?

    var body: some View {
        ChatTimelineScrollView(timeline: timeline)
            .safeAreaPadding(.bottom, inputHeight ?? 60)
            .overlay(alignment: .bottom) {
                ChatInputView(room: room.room, timeline: timeline, replyTo: $timeline.sendReplyTo, height: $inputHeight)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.room.displayName() ?? "Unknown room")
            .navigationSubtitle(toolbarSubtitle)
            .frame(minWidth: 250, minHeight: 200)
            .task {
                // ... existing task code
            }
    }
}
```

**Final:**
```swift
struct ChatJoinedRoom: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState  // NEW: Access window state
    @Bindable var timeline: LiveTimeline

    var room: LiveRoom {
        timeline.room
    }

    @State private var inputHeight: CGFloat?
    @FocusState private var inputFocused: Bool  // NEW: Manage focus state

    var body: some View {
        ChatTimelineScrollView(timeline: timeline)
            .safeAreaPadding(.bottom, inputHeight ?? 60)
            .overlay(alignment: .bottom) {
                ChatInputView(room: room.room, timeline: timeline, replyTo: $timeline.sendReplyTo, height: $inputHeight, focusState: $inputFocused)  // CHANGED: Pass focus state
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(room.room.displayName() ?? "Unknown room")
            .navigationSubtitle(toolbarSubtitle)
            .frame(minWidth: 250, minHeight: 200)
            .onAppear {  // NEW: Auto-focus on appear
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    inputFocused = true
                }
            }
            .onChange(of: windowState.shouldFocusInput) { _, shouldFocus in  // NEW: Handle focus trigger
                if shouldFocus {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        inputFocused = true
                        windowState.shouldFocusInput = false
                    }
                }
            }
            .task {
                // ... existing task code
            }
    }
}
```

---

### 3. **WindowState.swift** - Added focus trigger and navigation methods

**Original:**
```swift
@MainActor @Observable
final class WindowState {
    var selectedScreen: SelectedScreen = .none
    var selectedRoomId: String?
    var inspectorVisible: Bool = false
    var inspectorContent: InspectorContent = .roomInfo
    var searchQuery: String = ""
    var searchTokens: [SearchToken] = []
    var searchDirectResult: SearchDirectResult?

    // ... existing methods ...
}
```

**Final:**
```swift
@MainActor @Observable
final class WindowState {
    var selectedScreen: SelectedScreen = .none
    var selectedRoomId: String?
    var shouldFocusInput: Bool = false  // NEW: Focus trigger
    var inspectorVisible: Bool = false
    var inspectorContent: InspectorContent = .roomInfo
    var searchQuery: String = ""
    var searchTokens: [SearchToken] = []
    var searchDirectResult: SearchDirectResult?

    // ... existing methods ...

    // NEW: Navigate to previous room
    func selectPreviousRoom(rooms: [String]) {
        guard let currentRoomId = selectedRoomId,
              let currentIndex = rooms.firstIndex(of: currentRoomId),
              currentIndex > 0 else {
            return
        }
        selectedRoomId = rooms[currentIndex - 1]
        shouldFocusInput = true
    }

    // NEW: Navigate to next room
    func selectNextRoom(rooms: [String]) {
        guard let currentRoomId = selectedRoomId,
              let currentIndex = rooms.firstIndex(of: currentRoomId),
              currentIndex < rooms.count - 1 else {
            return
        }
        selectedRoomId = rooms[currentIndex + 1]
        shouldFocusInput = true
    }
}
```

---

### 4. **MatrixClient.swift** - Added centralized room organization logic

**Original:**
```swift
@MainActor @Observable
class MatrixClient {
    let storeID: String
    var client: ClientProtocol!
    var rooms: [SidebarRoom] = []
    var spaceService: LiveSpaceService!
    // ... rest of class
}
```

**Final:**
```swift
@MainActor @Observable
class MatrixClient {
    let storeID: String
    var client: ClientProtocol!
    var rooms: [SidebarRoom] = []
    var spaceService: LiveSpaceService!
    // ... rest of class

    // NEW: Computed property for organized room lists
    var organizedRooms: OrganizedRooms {
        let favorites = rooms.filter { $0.roomInfo?.isFavourite == true }
        let favoriteIDs = Set(favorites.map { $0.id })

        let directs = rooms.filter { room in
            let isDirect = room.roomInfo?.isDirect == true
            return isDirect && !favoriteIDs.contains(room.id)
        }

        let regularRooms = rooms.filter { room in
            let isSpace = room.room.isSpace()
            let isDirect = room.roomInfo?.isDirect == true
            return !isSpace && !isDirect && !favoriteIDs.contains(room.id)
        }

        let spaces = spaceService.spaceRooms

        return OrganizedRooms(
            favorites: favorites,
            directs: directs,
            rooms: regularRooms,
            spaces: spaces
        )
    }

    // NEW: Flat list of all room IDs in sidebar order
    var orderedRoomIds: [String] {
        let organized = organizedRooms
        var ids: [String] = []

        ids.append(contentsOf: organized.favorites.map { $0.id })
        ids.append(contentsOf: organized.directs.map { $0.id })
        ids.append(contentsOf: organized.rooms.map { $0.id })

        for space in organized.spaces {
            ids.append(space.id)
            if case let .loaded(children) = space.children {
                ids.append(contentsOf: children.rooms.map { $0.id })
            }
        }

        return ids
    }
}

// NEW: Structure to hold categorized rooms
struct OrganizedRooms {
    let favorites: [SidebarRoom]
    let directs: [SidebarRoom]
    let rooms: [SidebarRoom]
    let spaces: [SidebarSpaceRoom]
}
```

---

### 5. **SidebarView.swift** - Refactored to use centralized room organization

**Original:**
```swift
struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
    @State private var searchText: String = ""

    var favorites: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { $0.roomInfo?.isFavourite == true }
    }

    var directs: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { room in
                let isDirect = room.roomInfo?.isDirect == true
                let favoriteIDs = Set(favorites.map { $0.id })
                return isDirect && !favoriteIDs.contains(room.id)
            }
    }

    var rooms: [SidebarRoom] {
        (appState.matrixClient?.rooms ?? [])
            .filter { room in
                let isSpace = room.room.isSpace()
                let isDirect = room.roomInfo?.isDirect == true
                let favoriteIDs = Set(favorites.map(\.id))
                return !isSpace && !isDirect && !favoriteIDs.contains(room.id)
            }
    }

    var spaces: [SidebarSpaceRoom] {
        appState.matrixClient?.spaceService.spaceRooms ?? []
    }

    var body: some View {
        List(selection: $windowState.selectedRoomId) {
            // ...
            ForEach(favorites) { room in
            // ...
            ForEach(directs) { room in
            // ...
            ForEach(rooms) { room in
            // ...
            ForEach(spaces) { space in
        }
    }
}
```

**Final:**
```swift
struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState
    @State private var searchText: String = ""

    // CHANGED: Single computed property instead of four
    var organizedRooms: OrganizedRooms {
        appState.matrixClient?.organizedRooms ?? OrganizedRooms(
            favorites: [],
            directs: [],
            rooms: [],
            spaces: []
        )
    }

    var body: some View {
        List(selection: $windowState.selectedRoomId) {
            // ...
            ForEach(organizedRooms.favorites) { room in  // CHANGED
            // ...
            ForEach(organizedRooms.directs) { room in  // CHANGED
            // ...
            ForEach(organizedRooms.rooms) { room in  // CHANGED
            // ...
            ForEach(organizedRooms.spaces) { space in  // CHANGED
        }
    }
}
```

---

### 6. **Commands.swift** - Added keyboard shortcuts for room navigation

**Original:**
```swift
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
        // ... existing code
    }

    static func createRoomButton(windowState: WindowState) -> some View {
        // ... existing code
    }
}
```

**Final:**
```swift
import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    @FocusedValue(AppState.self) private var appState: AppState?  // NEW

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        TextEditingCommands()
        ToolbarCommands()
        newTab
        roomNavigation  // NEW
    }

    var newTab: some Commands {
        // ... existing code
    }

    static func createRoomButton(windowState: WindowState) -> some View {
        // ... existing code
    }

    // NEW: Room navigation commands
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
```

---

### 7. **MainView.swift** - Exposed AppState to focused scene values

**Original:**
```swift
var body: some View {
    NavigationSplitView(
        sidebar: { SidebarView() },
        detail: { details }
    )
    // ... other modifiers
    .modifier(ToolbarViewModifier())
    .modifier(SearchViewModifier())
    .environment(windowState)
    .focusedSceneValue(windowState)
}
```

**Final:**
```swift
var body: some View {
    NavigationSplitView(
        sidebar: { SidebarView() },
        detail: { details }
    )
    // ... other modifiers
    .modifier(ToolbarViewModifier())
    .modifier(SearchViewModifier())
    .environment(windowState)
    .focusedSceneValue(windowState)
    .focusedSceneValue(appState)  // NEW: Make AppState available to Commands
}
```

---

## Summary of Features Implemented

1. **Automatic Input Focus**: Message input field automatically receives focus when:
   - Opening a room for the first time
   - Navigating between rooms using keyboard shortcuts

2. **Keyboard Navigation**: Command+Shift+[ and Command+Shift+] to navigate through rooms while maintaining input focus

3. **Centralized Room Organization**: Room filtering logic moved from duplicated code in SidebarView and Commands to a single source of truth in MatrixClient

4. **Timing Fix**: 50ms delay ensures focus is applied after the new room view is fully rendered

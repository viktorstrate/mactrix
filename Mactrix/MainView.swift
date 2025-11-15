import SwiftUI
import MatrixRustSDK
import UI

struct MainView: View {
    @Environment(AppState.self) var appState
    
    @State private var windowState = WindowState()
    
    @State private var showWelcomeSheet: Bool = false
    @State private var inspectorVisible: Bool = false
    @State private var selectedRoomId: String? = nil
    
    @ViewBuilder var details: some View {
        switch windowState.selectedRoom {
        case .joinedRoom(let room):
            ChatView(room: room).id(room.id)
        case .previewRoom(let room):
            Text("Room Preview: \(room.info().name ?? "unknown name")")
        case nil:
            ContentUnavailableView("Select a room", systemImage: "message.fill")
        }
    }
    
    var body: some View {
        NavigationSplitView(
            sidebar: { SidebarView(selectedRoomId: $selectedRoomId) },
            detail: { details }
        )
        .environment(windowState)
        .inspector(isPresented: $inspectorVisible, content: {
            switch windowState.selectedRoom {
            case .joinedRoom(let room):
                UI.RoomInspectorView(room: room, members: room.fetchedMembers, inspectorVisible: $inspectorVisible)
            case .previewRoom(let room):
                Text("Preview room: \(room.info().name ?? "unknown name")")
            case nil:
                Text("No room selected")
            }
        })
        .task { await attemptLoadUserSession() }
        .sheet(isPresented: $showWelcomeSheet, onDismiss: onLoginModalDismiss ) {
            WelcomeSheetView()
        }
        .onChange(of: appState.matrixClient == nil) { _, matrixClientIsNil in
            if matrixClientIsNil {
                print("Matrix client is nil, present welcome sheet")
                showWelcomeSheet = true
            }
        }
        .task(id: selectedRoomId) {
            await onRoomSelected()
        }
        .onChange(of: appState.matrixClient?.authenticationFailed) { _, authFailed in
            if authFailed == true {
                print("Logging out since auth failed")
                appState.matrixClient = nil
            }
        }
    }
    
    func attemptLoadUserSession() async {
        guard appState.matrixClient == nil else { return }
        
        do {
            if let matrixClient = try await MatrixClient.attemptRestore() {
                appState.matrixClient = matrixClient
            }
        } catch {
            print("Failed to restore session: \(error)")
        }
        
        showWelcomeSheet = appState.matrixClient == nil
        if let matrixClient = appState.matrixClient {
            onMatrixLoaded(matrixClient: matrixClient)
        }
    }
    
    func onMatrixLoaded(matrixClient: MatrixClient) {
        Task {
            try await matrixClient.startSync()
        }
    }
    
    func onLoginModalDismiss() {
        Task {
            try await Task.sleep(for: .milliseconds(100))
            if let matrixClient = appState.matrixClient {
                onMatrixLoaded(matrixClient: matrixClient)
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    func onRoomSelected() async {
        guard let matrixClient = appState.matrixClient else { return }
        
        do {
            print("Selected room: \(selectedRoomId.debugDescription)")
            
            if let roomId = selectedRoomId {
                if let selectedRoom = try matrixClient.client.getRoom(roomId: roomId) {
                    self.windowState.selectedRoom = .joinedRoom(LiveRoom(room: selectedRoom))
                } else {
                    let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomId(roomId: roomId, viaServers: ["matrix.org"])
                    
                    print("Selected room preview: \(roomPreview.info())")
                    self.windowState.selectedRoom = .previewRoom(roomPreview)
                }
            } else {
                self.windowState.selectedRoom = nil
            }
        } catch {
            print("Failed to get room \(error)")
        }
    }
}

#Preview {
    MainView()
}

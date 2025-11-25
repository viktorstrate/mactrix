import MatrixRustSDK
import OSLog
import SwiftUI
import UI

struct MainView: View {
    @Environment(AppState.self) var appState

    @State private var windowState = WindowState()

    @State private var showWelcomeSheet: Bool = false

    @ViewBuilder var details: some View {
        switch windowState.selectedScreen {
        case let .joinedRoom(timeline: timeline):
            ChatView(timeline: timeline).id(timeline.room.id)
        case let .previewRoom(room):
            Text("Room Preview: \(room.info().name ?? "unknown name")")
            if let topic = room.info().topic {
                Text("Topic: \(topic)")
            }
        case .newRoom:
            UI.CreateRoomScreen(onSubmit: { params in
                guard let matrixClient = appState.matrixClient else { return }
                let newRoom = try await matrixClient.client.createRoom(request: params.asMatrixRequest)
                windowState.selectedRoomId = newRoom
            })
        case .none:
            ContentUnavailableView("Select a room", systemImage: "message.fill")
        }
    }

    var verificationSheetPresented: Binding<Bool> {
        Binding(
            get: { appState.matrixClient?.sessionVerificationData != nil },
            set: { isPresented in
                if !isPresented {
                    Task {
                        do {
                            try await appState.matrixClient?.client.getSessionVerificationController().declineVerification()
                        } catch {
                            Logger.viewCycle.error("failed to decline verification: \(error)")
                            appState.matrixClient?.sessionVerificationData = nil
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        @Bindable var windowState = windowState

        NavigationSplitView(
            sidebar: { SidebarView() },
            detail: { details }
        )
        .environment(windowState)
        .focusedSceneValue(windowState)
        .inspector(isPresented: $windowState.inspectorVisible, content: {
            InspectorScreen()
                .environment(windowState)
        })
        .task { await attemptLoadUserSession() }
        .sheet(isPresented: $showWelcomeSheet, onDismiss: onLoginModalDismiss) {
            WelcomeSheetView()
        }
        .sheet(isPresented: verificationSheetPresented, content: {
            if let verificationData = appState.matrixClient?.sessionVerificationData {
                UI.SessionVerificationModal(verificationData: verificationData.asModel, onComplete: { response in
                    Task {
                        switch response {
                        case .accept:
                            do {
                                try await appState.matrixClient?.client.getSessionVerificationController().approveVerification()
                            } catch {
                                Logger.viewCycle.error("failed to approve verification: \(error)")
                                appState.matrixClient?.sessionVerificationData = nil
                            }
                        case .decline:
                            do {
                                try await appState.matrixClient?.client.getSessionVerificationController().declineVerification()
                            } catch {
                                Logger.viewCycle.error("failed to decline verification: \(error)")
                                appState.matrixClient?.sessionVerificationData = nil
                            }
                        }
                    }
                })
            }
        })
        .onChange(of: appState.matrixClient == nil) { _, matrixClientIsNil in
            if matrixClientIsNil {
                Logger.viewCycle.info("Matrix client is nil, present welcome sheet")
                showWelcomeSheet = true
            }
        }
        .task(id: windowState.selectedRoomId) {
            await onRoomSelected()
        }
        .onChange(of: appState.matrixClient?.authenticationFailed) { _, authFailed in
            if authFailed == true {
                Logger.viewCycle.info("Logging out since auth failed")
                appState.matrixClient = nil
            }
        }
        .toolbar {
            Button {
                Logger.viewCycle.info("Show pins")
                windowState.showRoomPins()
            } label: {
                Label("Show Pins", systemImage: "pin.circle")
            }
            .help("Show Pins")
            .disabled(windowState.selectedRoomId == nil)

            Button {
                Logger.viewCycle.info("Show threads")
                windowState.showRoomThreads()
            } label: {
                Label("Show Threads", systemImage: "list.bullet.circle")
            }
            .help("Show Threads")
            .disabled(windowState.selectedRoomId == nil)

            if !windowState.inspectorVisible {
                HStack {
                    Divider()
                }
            }
        }
        .searchable(text: $windowState.searchQuery, tokens: $windowState.searchTokens, isPresented: windowState.searchFocused, placement: .automatic, prompt: "Search") { token in
            switch token {
            case .users:
                Text("Users")
            case .rooms:
                Text("Public Rooms")
            case .spaces:
                Text("Public Spaces")
            case .messages:
                Text("Messages")
            }
        }
        .searchSuggestions {
            if windowState.searchTokens.isEmpty {
                Label("Users", systemImage: "person").searchCompletion(SearchToken.users)
                Label("Public Rooms", systemImage: "number").searchCompletion(SearchToken.rooms)
                Label("Public Spaces", systemImage: "network").searchCompletion(SearchToken.spaces)
                Label("Messages", systemImage: "magnifyingglass.circle").searchCompletion(SearchToken.messages)
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
            Logger.viewCycle.error("Failed to restore matrix session: \(error)")
        }

        showWelcomeSheet = appState.matrixClient == nil
        if let matrixClient = appState.matrixClient {
            onMatrixLoaded(matrixClient: matrixClient)
        }
    }

    func onMatrixLoaded(matrixClient: MatrixClient) {
        Task {
            try await matrixClient.startSync()

            // check if a room is selected and load it
            await onRoomSelected()
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
            Logger.viewCycle.debug("Selected room: \(windowState.selectedRoomId.debugDescription)")

            if let roomId = windowState.selectedRoomId {
                if let selectedRoom = try matrixClient.client.getRoom(roomId: roomId) {
                    windowState.selectedScreen = .joinedRoom(timeline: LiveTimeline(room: LiveRoom(matrixRoom: selectedRoom)))
                } else {
                    let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomId(roomId: roomId, viaServers: ["matrix.org"])

                    Logger.viewCycle.debug("Selected room preview: \(roomPreview.info().debugDescription)")
                    windowState.selectedScreen = .previewRoom(roomPreview)
                }
            } else {
                windowState.selectedScreen = .none
            }
        } catch {
            Logger.viewCycle.error("Failed to get room \(error)")
        }
    }
}

#Preview {
    MainView()
}

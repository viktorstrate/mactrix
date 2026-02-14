import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import Utils

struct MainView: View {
    @Environment(AppState.self) var appState

    @State private var windowState = WindowState()

    @State private var showWelcomeSheet: Bool = false

    @ViewBuilder var details: some View {
        switch windowState.selectedScreen {
        case .joinedRoom(timeline: let timeline):
            ChatView(timeline: timeline).id(timeline.room.id)
        case .previewRoom(let room):
            UI.RoomPreviewView(
                preview: room.info(),
                imageLoader: appState.matrixClient,
                actions: appState.matrixClient?.roomPreviewActions(forRoomWithId: room.info().roomId, windowState: windowState)
            )
        case .newRoom:
            UI.CreateRoomScreen(onSubmit: { params in
                guard let matrixClient = appState.matrixClient else { return }
                let newRoom = try await matrixClient.client.createRoom(request: params.asMatrixRequest)
                windowState.selectedRoomId = newRoom
            })
        case .loadMatrixUrl(let matrixUri):
            LoadMatrixUriScreen(matrixUri: matrixUri)
        case .user(profile: let profile):
            UserProfileView(
                profile: profile,
                isUserIgnored: appState.matrixClient?.isUserIgnored(profile.userId) ?? false,
                actions: appState.matrixClient?.userProfileActions(forUserId: profile.userId, windowState: windowState),
                timelineActions: nil,
                imageLoader: appState.matrixClient)
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
        .onOpenURL { url in
            Logger.viewCycle.debug("onOpenUrl \(url)")

            do {
                let matrixUri = try Utils.MatrixUriScheme(parseUrl: url.absoluteString)
                Logger.viewCycle.info("Matched Matrix Uri")

                windowState.selectedScreen = .loadMatrixUrl(matrixUri)
            } catch {
                Logger.viewCycle.error("Failed to parse Matrix Uri: \(error)")
            }
        }
        .modifier(ToolbarViewModifier())
        .modifier(SearchViewModifier())
        .environment(windowState)
        .focusedSceneValue(windowState)
        .focusedSceneValue(appState)
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

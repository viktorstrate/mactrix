import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

public struct MainView: View {
  @Environment(AppState.self) var appState

  @SceneStorage("MainView.windowState")
  private var windowState: WindowState = .init()

  @State private var showWelcomeSheet: Bool = false

  let x: Bool = false

  public init() {}

  @ViewBuilder var details: some View {
    let screen = windowState.selectedScreen
    switch screen.content {
    case .joinedRoom(let timeline):
      ChatView(timeline: timeline).id(timeline.room.id)
    case .previewRoom(let room, let eventId, let routingVia):
      MactrixUI.RoomPreviewView(
        preview: room.info(),
        imageLoader: appState.matrixClient,
        actions: appState.matrixClient?.roomPreviewActions(
          forRoomWithId: room.info().roomId, windowState: windowState,
          eventId: eventId, routingVia: routingVia)
      )
      .id(screen.id)
    case .newRoom:
      MactrixUI.CreateRoomScreen(onSubmit: { params in
        guard let matrixClient = appState.matrixClient else { return }
        guard windowState.selectedScreen === screen else { return }
        let newRoom = try await matrixClient.client.createRoom(
          request: params.asMatrixRequest)
        try Task.checkCancellation()
        guard windowState.selectedScreen === screen, appState.matrixClient === matrixClient else {
          return
        }
        windowState.selectRoom(newRoom)
      })
    case .loadingRoom, .loadMatrixUrl:
      LoadDestinationScreen(screen: screen)
        .id(screen.id)
    case .user(let profile):
      UserProfileView(
        profile: profile,
        isUserIgnored: appState.matrixClient?.isUserIgnored(profile.userId) ?? false,
        actions: appState.matrixClient?.userProfileActions(
          forUserId: profile.userId, windowState: windowState),
        timelineActions: nil,
        imageLoader: appState.matrixClient
      )
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
              try await appState.matrixClient?.client
                .getSessionVerificationController().declineVerification()
            } catch {
              Logger.viewCycle.error("failed to decline verification: \(error)")
              appState.matrixClient?.sessionVerificationData = nil
            }
          }
        }
      }
    )
  }

  public var body: some View {
    @Bindable var windowState = windowState

    NavigationSplitView(
      sidebar: { SidebarView() },
      detail: { details }
    )
    .inspector(
      isPresented: $windowState.inspectorVisible,
      content: {
        InspectorScreen()
          .environment(windowState)
      }
    )
    .background {
      let matrixClient = appState.matrixClient
      QuickNavigationOverlayAttachment(
        coordinator: windowState.quickNavigation, matrixClient: matrixClient,
        onSelectRoom: { [weak windowState] roomID in
          windowState?.selectRoom(roomID)
        })
    }
    .task { await attemptLoadUserSession() }
    .sheet(isPresented: $showWelcomeSheet, onDismiss: onLoginModalDismiss) {
      WelcomeSheetView()
    }
    .sheet(
      isPresented: verificationSheetPresented,
      content: {
        if let verificationData = appState.matrixClient?.sessionVerificationData {
          MactrixUI.SessionVerificationModal(
            verificationData: verificationData.asModel,
            onComplete: { response in
              Task {
                switch response {
                case .accept:
                  do {
                    try await appState.matrixClient?.client
                      .getSessionVerificationController()
                      .approveVerification()
                  } catch {
                    Logger.viewCycle.error(
                      "failed to approve verification: \(error)")
                    appState.matrixClient?.sessionVerificationData = nil
                  }
                case .decline:
                  do {
                    try await appState.matrixClient?.client
                      .getSessionVerificationController()
                      .declineVerification()
                  } catch {
                    Logger.viewCycle.error(
                      "failed to decline verification: \(error)")
                    appState.matrixClient?.sessionVerificationData = nil
                  }
                }
              }
            })
        }
      }
    )
    .onChange(of: appState.matrixClient == nil) { _, matrixClientIsNil in
      if matrixClientIsNil {
        Logger.viewCycle.info("Matrix client is nil, present welcome sheet")
        showWelcomeSheet = true
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
      do {
        try await matrixClient.startSync()
      } catch {
        Logger.matrixClient.error("Failed to start sync: \(error)")
      }
    }
  }

  func onLoginModalDismiss() {
    Task {
      do {
        try await Task.sleep(for: .milliseconds(100))
        if let matrixClient = appState.matrixClient {
          onMatrixLoaded(matrixClient: matrixClient)
        } else {
          NSApp.terminate(nil)
        }
      } catch is CancellationError {
        // ignore
      } catch {
        Logger.matrixClient.error("Failed in onLoginModalDismiss: \(error)")
      }
    }
  }
}

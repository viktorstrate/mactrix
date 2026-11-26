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
        imageLoader: windowState.matrixClient,
        actions: windowState.matrixClient?.roomPreviewActions(
          forRoomWithId: room.info().roomId, windowState: windowState,
          eventId: eventId, routingVia: routingVia)
      )
      .id(screen.id)
    case .newRoom:
      MactrixUI.CreateRoomScreen(onSubmit: { params in
        guard let matrixClient = windowState.matrixClient else { return }
        guard windowState.selectedScreen === screen else { return }
        let newRoom = try await matrixClient.client.createRoom(
          request: params.asMatrixRequest)
        try Task.checkCancellation()
        guard windowState.selectedScreen === screen, windowState.matrixClient === matrixClient
        else {
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
        isUserIgnored: windowState.matrixClient?.isUserIgnored(profile.userId) ?? false,
        actions: windowState.matrixClient?.userProfileActions(
          forUserId: profile.userId, windowState: windowState),
        timelineActions: nil,
        imageLoader: windowState.matrixClient
      )
    case .none:
      ContentUnavailableView("Select a room", systemImage: "message.fill")
    }
  }

  var verificationSheetPresented: Binding<Bool> {
    Binding(
      get: { windowState.matrixClient?.sessionVerificationData != nil },
      set: { isPresented in
        if !isPresented {
          Task {
            do {
              try await windowState.matrixClient?.client
                .getSessionVerificationController().declineVerification()
            } catch {
              Logger.viewCycle.error("failed to decline verification: \(error)")
              windowState.matrixClient?.sessionVerificationData = nil
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
      let matrixClient = windowState.matrixClient
      QuickNavigationOverlayAttachment(
        coordinator: windowState.quickNavigation, matrixClient: matrixClient,
        onSelectRoom: { [weak windowState] roomID in
          windowState?.selectRoom(roomID)
        })
    }
    .task { await attemptLoadUserSession() }
    .sheet(item: $windowState.loginSheet, onDismiss: onLoginModalDismiss) { request in
      WelcomeSheetView(request: request)
    }
    .sheet(
      isPresented: verificationSheetPresented,
      content: {
        if let verificationData = windowState.matrixClient?.sessionVerificationData {
          MactrixUI.SessionVerificationModal(
            verificationData: verificationData.asModel,
            onComplete: { response in
              Task {
                switch response {
                case .accept:
                  do {
                    try await windowState.matrixClient?.client
                      .getSessionVerificationController()
                      .approveVerification()
                  } catch {
                    Logger.viewCycle.error(
                      "failed to approve verification: \(error)")
                    windowState.matrixClient?.sessionVerificationData = nil
                  }
                case .decline:
                  do {
                    try await windowState.matrixClient?.client
                      .getSessionVerificationController()
                      .declineVerification()
                  } catch {
                    Logger.viewCycle.error(
                      "failed to decline verification: \(error)")
                    windowState.matrixClient?.sessionVerificationData = nil
                  }
                }
              }
            })
        }
      }
    )
    .onChange(of: appState.restoration, initial: true) { _, restoration in
      guard case .restored(let activeAccountID) = restoration else { return }
      windowState.showAccount(
        appState.matrixClient, knownAccountIDs: Set(appState.accounts.map(\.storeID)))
      if activeAccountID == nil {
        Logger.viewCycle.info("No signed in accounts, present welcome sheet")
        windowState.loginSheet = .firstAccount
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
    await appState.restoreAccounts()
  }

  func onLoginModalDismiss() {
    Task {
      do {
        try await Task.sleep(for: .milliseconds(100))
        if appState.accounts.isEmpty {
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

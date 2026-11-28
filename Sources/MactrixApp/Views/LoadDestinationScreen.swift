import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

struct LoadDestinationScreen: View {
  @Environment(WindowState.self) var windowState

  let screen: SelectedScreen

  @State private var errorMessage: String?
  @State private var retryAttempt = 0

  private struct LoadRequest: Hashable {
    let attempt: Int
    let client: ObjectIdentifier?
  }

  private var loadingDescription: String {
    switch screen.content {
    case .loadingRoom(let roomId):
      String(localized: "Loading room \(roomId)")
    case .loadMatrixUrl(let uri):
      switch uri.kind {
      case .roomAlias(let alias): String(localized: "Loading room \(alias)")
      case .roomId(let roomId): String(localized: "Loading room \(roomId)")
      case .user(let userId): String(localized: "Loading user \(userId)")
      }
    default:
      String(localized: "Loading…")
    }
  }

  var body: some View {
    VStack(spacing: 12) {
      if let errorMessage {
        ContentUnavailableView {
          Label("Could not open destination", systemImage: "exclamationmark.triangle")
        } description: {
          Text(errorMessage)
        } actions: {
          Button("Try Again") { retryAttempt += 1 }
          Button("Close") { windowState.selectedScreen = .none }
        }
      } else {
        ProgressView { Text(loadingDescription) }
        Button("Cancel") { windowState.selectedScreen = .none }
      }
    }
    .task(
      id: LoadRequest(
        attempt: retryAttempt, client: windowState.matrixClient.map { ObjectIdentifier($0) })
    ) {
      await load()
    }
  }

  @MainActor
  private func load() async {
    guard windowState.selectedScreen === screen, !Task.isCancelled else { return }
    errorMessage = nil
    guard let matrixClient = windowState.matrixClient else {
      errorMessage = String(localized: "Sign in to continue.")
      return
    }

    do {
      let destination = try await resolve(using: matrixClient)
      try Task.checkCancellation()
      guard windowState.selectedScreen === screen, windowState.matrixClient === matrixClient else {
        return
      }
      windowState.selectedScreen = destination
    } catch {
      guard !Task.isCancelled, windowState.selectedScreen === screen,
        windowState.matrixClient === matrixClient
      else { return }
      Logger.viewCycle.error("Failed to open destination: \(error)")
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func resolve(using matrixClient: MatrixClient) async throws -> SelectedScreen {
    try Task.checkCancellation()
    switch screen.content {
    case .loadingRoom(let roomId):
      if let room = try matrixClient.client.getRoom(roomId: roomId) {
        return .joinedRoom(
          timeline: LiveTimeline(room: LiveRoom(matrixRoom: room, matrixClient: matrixClient)))
      } else {
        return .previewRoom(
          try await matrixClient.client.getRoomPreviewFromRoomId(
            roomId: roomId, viaServers: matrixClient.viaServers))
      }
    case .loadMatrixUrl(let uri):
      let roomId: String
      var routingVia = uri.routingVia
      switch uri.kind {
      case .user(let userId):
        return .user(profile: try await matrixClient.client.getProfile(userId: userId))
      case .roomId(let id):
        roomId = id
      case .roomAlias(let alias):
        guard let resolved = try await matrixClient.client.resolveRoomAlias(roomAlias: alias) else {
          throw MatrixUriError.parserError(reason: "Room alias could not be resolved.")
        }
        roomId = resolved.roomId
        routingVia.append(contentsOf: resolved.servers)
      }

      try Task.checkCancellation()
      guard windowState.selectedScreen === screen, windowState.matrixClient === matrixClient else {
        throw CancellationError()
      }

      if let room = try matrixClient.client.getRoom(roomId: roomId), room.membership() == .joined {
        let focus: LiveTimeline.Focus = uri.event.map { .event(eventId: $0) } ?? .live
        return .joinedRoom(
          timeline: LiveTimeline(
            room: LiveRoom(matrixRoom: room, matrixClient: matrixClient),
            focus: focus))
      } else {
        let preview = try await matrixClient.client.getRoomPreviewFromRoomId(
          roomId: roomId, viaServers: matrixClient.routingServers(hints: routingVia))
        return .previewRoom(preview, eventId: uri.event, routingVia: routingVia)
      }
    default:
      return screen
    }
  }
}

import MatrixRustSDK
import OSLog
import SwiftUI
import MactrixApp

struct SearchViewModifier: ViewModifier {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    func body(content: Content) -> some View {
        @Bindable var windowState = windowState
        content
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
                case let .resolvedRoomAlias(alias: alias, resolvedRoom: _):
                    Text(alias)
                case let .resolvedRoomId(roomPreview: preview):
                    Text(preview.info().roomId)
                case let .resolvedUser(profile: userProfile):
                    Text(userProfile.userId)
                }
            }
            .searchSuggestions {
                searchSuggestions
            }
            .task(id: windowState.searchQuery) {
                await calculateDirectSearchResults()
            }
    }

    @ViewBuilder
    var searchSuggestions: some View {
        switch windowState.searchDirectResult {
        case .lookingForRoom:
            HStack {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Searching for room")
                    .foregroundStyle(.secondary)
            }
            Divider()
        case .lookingForUser(userId: _):
            HStack {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Searching for user")
                    .foregroundStyle(.secondary)
            }
            Divider()
        case .roomNotFound:
            Label("Room not found", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Divider()
        case .userNotFound(userId: _):
            Label("User not found", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Divider()
        case let .resolvedRoomAlias(alias: alias, resolvedRoom: resolvedRoom):
            HStack(alignment: .firstTextBaseline) {
                Text("room")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(alias)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .searchCompletion(SearchToken.resolvedRoomAlias(alias: alias, resolvedRoom: resolvedRoom))
            Divider()
        case let .resolvedRoomId(roomPreview: roomPreview):
            HStack(alignment: .firstTextBaseline) {
                Text("room")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(roomPreview.info().roomId)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .searchCompletion(SearchToken.resolvedRoomId(roomPreview: roomPreview))
            Divider()
        case let .resolvedUser(profile: userProfile):
            HStack(alignment: .firstTextBaseline) {
                Text("user")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(userProfile.userId)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .searchCompletion(SearchToken.resolvedUser(profile: userProfile))
            Divider()
        case nil:
            EmptyView()
        }

        if windowState.searchTokens.isEmpty {
            Label("Users", systemImage: "person").searchCompletion(SearchToken.users)
            Label("Public Rooms", systemImage: "number").searchCompletion(SearchToken.rooms)
            Label("Public Spaces", systemImage: "network").searchCompletion(SearchToken.spaces)
            Label("Messages", systemImage: "magnifyingglass.circle").searchCompletion(SearchToken.messages)
        }
    }

    func calculateDirectSearchResults() async {
        let query: String = {
            var result = windowState.searchQuery.trimmingCharacters(in: .whitespaces)

            let matrixToPrefix = "https://matrix.to/#/"
            if result.starts(with: matrixToPrefix) {
                result = String(result.dropFirst(matrixToPrefix.count))
                result = result.removingPercentEncoding ?? result
            }

            if result.starts(with: "@") {
                result = result.lowercased()
            }

            return result
        }()

        do {
            guard let matrixClient = appState.matrixClient else { return }
            try await Task.sleep(for: .milliseconds(300))

            let roomAliasRegex = /\#[^:]+\:[^\s]*/
            let userIdRegex = /\@[a-z0-9._=\-\/+]+\:[^\s]*/
            let roomIdRegex = /\![^:]+\:[^\s]*/

            if try roomAliasRegex.wholeMatch(in: query) != nil {
                Logger.viewCycle.debug("Matched room alias in query: \(query)")
                windowState.searchDirectResult = .lookingForRoom(alias: query)
                if let resolvedRoom = try await matrixClient.client.resolveRoomAlias(roomAlias: query) {
                    windowState.searchDirectResult = .resolvedRoomAlias(alias: query, resolvedRoom: resolvedRoom)
                } else {
                    windowState.searchDirectResult = .roomNotFound(alias: query)
                }
            } else if try userIdRegex.wholeMatch(in: query) != nil {
                Logger.viewCycle.debug("Matched user id in query: \(query)")
                windowState.searchDirectResult = .lookingForUser(userId: query)
                do {
                    let userProfile = try await matrixClient.client.getProfile(userId: query)
                    windowState.searchDirectResult = .resolvedUser(profile: userProfile)
                } catch {
                    Logger.viewCycle.error("failed to resolve user \(query): \(error)")
                    windowState.searchDirectResult = .userNotFound(userId: query)
                }
            } else if try roomIdRegex.wholeMatch(in: query) != nil {
                Logger.viewCycle.debug("Matched room id in query: \(query)")
                windowState.searchDirectResult = .lookingForRoom(alias: query)
                do {
                    let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomId(roomId: query, viaServers: ["matrix.org"])
                    windowState.searchDirectResult = .resolvedRoomId(roomPreview: roomPreview)
                } catch {
                    Logger.viewCycle.error("failed to resolve room id \(query): \(error)")
                    windowState.searchDirectResult = .roomNotFound(alias: query)
                }
            } else {
                windowState.searchDirectResult = nil
            }
        } catch is CancellationError {}
        catch {
            Logger.viewCycle.error("failed to resolve search query '\(query)': \(error)")
        }
    }
}

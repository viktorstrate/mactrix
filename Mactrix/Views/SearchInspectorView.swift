import MatrixRustSDK
import SwiftUI
import UI

struct SearchUserPopover: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    let user: UserProfile

    var body: some View {
        VStack {
            if let displayName = user.displayName {
                Text(displayName)
            }

            Text(user.userId)

            Button("Send DM", action: openUserRoom)
        }
        .padding()
    }

    func openUserRoom() {
        guard let matrixClient = appState.matrixClient else { return }

        Task {
            do {
                if let room = try matrixClient.client.getDmRoom(userId: user.id) {
                    windowState.selectedRoomId = room.id
                    return
                }

                let createRoomParams = CreateRoomParameters(
                    name: nil, isEncrypted: false, isDirect: true, visibility: .private,
                    preset: .privateChat, invite: [user.userId]
                )
                let roomId = try await matrixClient.client.createRoom(request: createRoomParams)
                windowState.selectedRoomId = roomId
            } catch {
                print("failed to get DM room for user \(user.id): \(error)")
            }
        }
    }
}

struct SearchInspectorView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State var searchedUsers: [UserProfile] = []
    @State var searching: Bool = false
    @State var userListSelection: String? = nil

    @ViewBuilder
    var searchUsers: some View {
        List(selection: $userListSelection) {
            Section("User search results") {
                if searching {
                    Group {
                        Text("First user")
                        Text("Second user")
                        Text("Third user")
                    }.redacted(reason: .placeholder)
                } else {
                    ForEach(searchedUsers) { user in
                        UI.UserProfileRow(userProfile: user, imageLoader: appState.matrixClient)
                            .popover(
                                isPresented: Binding(
                                    get: { userListSelection == user.id },
                                    set: { _ in userListSelection = nil }
                                ),
                                arrowEdge: .leading
                            ) {
                                SearchUserPopover(user: user)
                            }
                    }
                }
            }
        }
        .task(id: windowState.searchQuery) {
            do {
                guard let matrixClient = appState.matrixClient else { return }
                guard !windowState.searchQuery.isEmpty else {
                    searchedUsers = []
                    return
                }

                searching = true
                defer { searching = false }

                try await Task.sleep(for: .milliseconds(500))

                let results = try await matrixClient.client.searchUsers(searchTerm: windowState.searchQuery, limit: 100)

                searchedUsers = results.results
            } catch is CancellationError {
                /* search cancelled */
            } catch {
                print("user search failed: \(error)")
            }
        }
    }

    @ViewBuilder
    var viewSelector: some View {
        if windowState.searchTokens.contains(.messages) {
            Text("Search messages")
        } else if windowState.searchTokens.contains(.rooms) {
            Text("Search rooms")
        } else if windowState.searchTokens.contains(.spaces) {
            Text("Search spaces")
        } else if windowState.searchTokens.contains(.users) {
            searchUsers
        } else {
            Text("Select a search term")
        }
    }

    var body: some View {
        viewSelector
            .inspectorColumnWidth(min: 300, ideal: 300, max: 400)
    }
}

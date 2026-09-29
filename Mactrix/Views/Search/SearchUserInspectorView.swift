import MatrixRustSDK
import OSLog
import SwiftUI
import UI

struct SearchUserInspectorView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @State var searchedUsers: [UserProfile] = []
    @State var searching: Bool = false
    @State var userListSelection: String? = nil

    var body: some View {
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
                        MactrixUI.UserProfileRow(profile: user, imageLoader: appState.matrixClient)
                    }
                }
            }
        }
        .onChange(of: userListSelection) { _, selectedUserId in
            if let user = searchedUsers.first(where: { $0.id == selectedUserId }) {
                windowState.selectedScreen = .user(profile: user)
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
                Logger.viewCycle.error("user search failed: \(error)")
            }
        }
    }
}

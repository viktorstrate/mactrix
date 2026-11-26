import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct SearchMessagesInspectorView: View {
  @Environment(AppState.self) var appState
  @Environment(WindowState.self) var windowState

  @State var selectedMessage: String? = nil

  @State var searchService: LiveSearchService? = nil

  @ViewBuilder
  var content: some View {
    ForEach(searchService?.results ?? []) { searchResult in
      VStack(alignment: .leading) {
        Text(searchResult.message.sender)
          .help(searchResult.message.sender)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(searchResult.message.content.userInterfaceText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1...3)
          .truncationMode(.tail)
      }
    }
  }

  var body: some View {
    List(selection: $selectedMessage) {
      Section(
        content: { content },
        header: {
          HStack {
            Text("Message results")
            if searchService?.paginationState == .loading {
              ProgressView().controlSize(.mini)
            }
          }
        })
    }
    .onChange(of: selectedMessage) {
      guard let selectedMessage else { return }
      guard let message = searchService?.results.first(where: { $0.id == selectedMessage }) else {
        Logger.matrixClient.warning("selected search message was not found in results")
        return
      }

      windowState.selectEvent(roomId: message.roomId, eventId: message.id)
    }
    .task(id: windowState.searchQuery) {
      do {
        guard let matrixClient = appState.matrixClient else { return }

        let searchService: LiveSearchService
        if let s = self.searchService {
          searchService = s
        } else {
          searchService = await LiveSearchService(
            searchService: matrixClient.client.searchService())
          self.searchService = searchService
        }

        try await Task.sleep(for: .milliseconds(500))

        try await searchService.search(query: windowState.searchQuery)
      } catch is CancellationError {
        /* search cancelled */
      } catch {
        Logger.viewCycle.error("message search failed: \(error)")
      }
    }
  }
}

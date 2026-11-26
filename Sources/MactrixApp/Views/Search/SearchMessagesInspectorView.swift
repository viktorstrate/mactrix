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
    let results = searchService?.results ?? []
    let query = windowState.searchQuery
    ForEach(results) { searchResult in
      let paginationQuery =
        searchResult.id == results.last?.id && searchService?.activeQuery == query ? query : nil

      SearchMessageRowView(result: searchResult, query: query, matrixClient: appState.matrixClient)
        .task(id: paginationQuery) {
          guard let paginationQuery, paginationQuery == windowState.searchQuery else { return }
          do {
            try await searchService?.loadMore(after: searchResult.id, for: paginationQuery)
          } catch is CancellationError {
            // The last row or search query changed before pagination started.
          } catch {
            Logger.viewCycle.error("message search pagination failed: \(error)")
          }
        }
    }
  }

  var body: some View {
    let query = windowState.searchQuery
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
    .task(id: query) {
      do {
        try await Task.sleep(for: .milliseconds(500))
        guard let matrixClient = appState.matrixClient else { return }

        let searchService: LiveSearchService
        if let s = self.searchService {
          searchService = s
        } else {
          searchService = await LiveSearchService(
            searchService: matrixClient.client.searchService())
          try Task.checkCancellation()
          self.searchService = searchService
        }

        try await searchService.search(query: query)
      } catch is CancellationError {
        /* search cancelled */
      } catch {
        Logger.viewCycle.error("message search failed: \(error)")
      }
    }
  }
}

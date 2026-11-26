import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public class LiveSearchService {
  public let searchService: SearchService
  public private(set) var results: [SearchServiceResult] = []
  public private(set) var paginationState: SearchServicePaginationState = .loading

  @ObservationIgnored fileprivate var resultsHandle: TaskHandle?
  @ObservationIgnored fileprivate var paginationHandle: TaskHandle?

  public init(searchService: SearchService) async {
    self.searchService = searchService
    listenForPaginationStatus()
    await listenForSearchResults()
  }

  private func listenForSearchResults() async {
    let searchListener = AsyncSDKListener<[MatrixRustSDK.SearchServiceResultsUpdate]>()
    resultsHandle = await self.searchService.subscribeToResults(listener: searchListener)

    Task { [weak self] in
      for await updates in searchListener {
        guard let self else { break }
        for change in updates {
          switch change {
          case .append(let values):
            results.append(contentsOf: values)
          case .clear:
            results = []
          case .pushFront(let value):
            results.insert(value, at: 0)
          case .pushBack(let value):
            results.append(value)
          case .popFront:
            results.removeFirst()
          case .popBack:
            results.removeLast()
          case .insert(let index, let value):
            results.insert(value, at: Int(index))
          case .set(let index, let value):
            results[Int(index)] = value
          case .remove(let index):
            results.remove(at: Int(index))
          case .truncate(let length):
            results.removeSubrange(Int(length)..<self.results.count)
          case .reset(let values):
            results = values
          }
        }
      }
    }
  }

  private func listenForPaginationStatus() {
    let paginationListener = AsyncSDKListener<SearchServicePaginationState>()
    paginationHandle = self.searchService
      .subscribeToPaginationStateUpdates(listener: paginationListener)

    Task { [weak self] in
      for await status in paginationListener {
        guard let self else { break }
        self.paginationState = status
      }
    }
  }

  public func search(query: String) async throws {
    try await searchService.setQuery(query: query)
  }
}

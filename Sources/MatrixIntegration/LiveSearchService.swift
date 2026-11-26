import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public class LiveSearchService {
  public let searchService: SearchService
  public private(set) var results: [SearchServiceResult] = []
  public private(set) var paginationState: SearchServicePaginationState = .loading
  public private(set) var activeQuery: String?

  @ObservationIgnored private var request: Task<Void, Error>?
  @ObservationIgnored private var lastPaginatedEventID: String?
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
    try Task.checkCancellation()
    activeQuery = nil
    while let request {
      _ = await request.result
      try Task.checkCancellation()
    }
    lastPaginatedEventID = nil

    let request = startRequest { try await self.searchService.setQuery(query: query) }
    try await request.value
    try Task.checkCancellation()
    activeQuery = query
  }

  public func loadMore(after eventID: String, for query: String) async throws {
    try Task.checkCancellation()
    while let request {
      _ = await request.result
      try Task.checkCancellation()
    }
    guard activeQuery == query,
      results.last?.id == eventID,
      lastPaginatedEventID != eventID,
      searchService.paginationState() == .idle(endReached: false)
    else { return }

    lastPaginatedEventID = eventID
    let request = startRequest { try await self.searchService.paginate() }
    try await request.value
  }

  private func startRequest(_ operation: @escaping @MainActor () async throws -> Void)
    -> Task<Void, Error>
  {
    // Let the SDK finish updating its cursor even if SwiftUI cancels the row or query task.
    let request = Task {
      defer { self.request = nil }
      try await operation()
    }
    self.request = request
    return request
  }
}

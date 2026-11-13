import XCTest
@testable import WhaleAgent

@MainActor
private final class ControlledMarket: MarketDataProvider {
    var searches: [(String, CheckedContinuation<MarketSearchResponse, Error>)] = []
    var quoteRequests: [CheckedContinuation<MarketQuoteResponse, Error>] = []
    func search(_ query: String) async throws -> MarketSearchResponse {
        try await withCheckedThrowingContinuation { searches.append((query, $0)) }
    }
    func indexes(force: Bool) async throws -> MarketQuoteResponse {
        MarketQuoteResponse(updatedAt: ToolDate.iso(Date()), delayedMinutes: nil, source: "test", quotes: [], errors: [])
    }
    func quotes(symbols: [String], force: Bool) async throws -> MarketQuoteResponse {
        try await withCheckedThrowingContinuation { quoteRequests.append($0) }
    }
    func todayFundFlows(symbols: [String]) async -> [String: FundFlowPoint] { [:] }
}

@MainActor
final class DiscoverRaceTests: XCTestCase {
    private func waitUntil(_ ready: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !ready() && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        guard ready() else { throw NSError(domain: "TestWait", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider request was not dispatched"]) }
    }
    func testOldSearchFailureCannotEraseNewSuccess() async throws {
        let provider = ControlledMarket()
        let model = DiscoverModel(initialChannel: .market, marketProvider: provider)
        model.searchQuery = "旧查询"
        let old = Task { await model.searchNow() }
        try await waitUntil { provider.searches.count >= 1 }
        model.searchQuery = "新查询"
        let latest = Task { await model.searchNow() }
        try await waitUntil { provider.searches.count >= 2 }
        let match = StockSearchResult(symbol: "sh600519", code: "600519", name: "新结果", market: "SH", type: "stock")
        provider.searches[1].1.resume(returning: MarketSearchResponse(query: "新查询", results: [match], source: "test"))
        await latest.value
        provider.searches[0].1.resume(throwing: URLError(.timedOut))
        await old.value
        XCTAssertEqual(model.searchResults.map(\.name), ["新结果"])
        XCTAssertEqual(model.searchState, .loaded)
    }

    func testIdenticalQueryStillRejectsOlderGeneration() async throws {
        let provider = ControlledMarket()
        let model = DiscoverModel(initialChannel: .market, marketProvider: provider)
        model.searchQuery = "茅台"
        let old = Task { await model.searchNow() }
        try await waitUntil { provider.searches.count >= 1 }
        let latest = Task { await model.searchNow() }
        try await waitUntil { provider.searches.count >= 2 }
        let match = StockSearchResult(symbol: "sh600519", code: "600519", name: "最新结果", market: "SH", type: "stock")
        provider.searches[1].1.resume(returning: MarketSearchResponse(query: "茅台", results: [match], source: "test"))
        await latest.value
        provider.searches[0].1.resume(returning: MarketSearchResponse(query: "茅台", results: [], source: "test"))
        await old.value
        XCTAssertEqual(model.searchResults.map(\.name), ["最新结果"])
    }

    func testRemovedWatchSymbolCannotReturnFromOutstandingResponse() async throws {
        let suite = "whale.race.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["sh600519"], forKey: WatchlistStore.storageKey)
        let store = WatchlistStore(defaults: defaults)
        let provider = ControlledMarket()
        let model = DiscoverModel(initialChannel: .market, marketProvider: provider, watchlistStore: store)
        let old = Task { await model.loadMarket(force: true) }
        try await waitUntil { !provider.quoteRequests.isEmpty }
        model.removeFromWatchlist("sh600519")
        let json = """
        {"symbol":"sh600519","code":"600519","market":"SH","name":"旧报价","price":100}
        """
        let quote = try JSONDecoder().decode(StockQuote.self, from: Data(json.utf8))
        provider.quoteRequests[0].resume(returning: MarketQuoteResponse(updatedAt: ToolDate.iso(Date()), delayedMinutes: nil, source: "test", quotes: [quote], errors: []))
        await old.value
        XCTAssertTrue(model.watchlist.isEmpty)
        XCTAssertTrue(model.watchQuotes.isEmpty)
    }
}

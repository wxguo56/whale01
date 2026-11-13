import Foundation

/// Injectable boundary for market I/O. UI generations and watchlist snapshots
/// can be verified without a live quotation provider or model credentials.
protocol MarketDataProvider: AnyObject {
    func indexes(force: Bool) async throws -> MarketQuoteResponse
    func quotes(symbols: [String], force: Bool) async throws -> MarketQuoteResponse
    func search(_ query: String) async throws -> MarketSearchResponse
    func todayFundFlows(symbols: [String]) async -> [String: FundFlowPoint]
}
extension DiscoverClient: MarketDataProvider {}

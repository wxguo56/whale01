import Combine
import Foundation
import SwiftUI

@MainActor
final class DiscoverModel: ObservableObject {
    let client = DiscoverClient()
    private let store = WatchlistStore.shared
    private var newsCache: [DiscoverChannel: (response: NewsFeedResponse, at: Date)] = [:]
    private var rankCache: [GameRankBoard: (response: GameRankResponse, at: Date)] = [:]
    private var loadedNewsChannel: DiscoverChannel?
    private var loadedRankBoard: GameRankBoard?
    private var searchTask: Task<Void, Never>?
    private var requestToken = UUID()
    private var watchlistCancellable: AnyCancellable?

    @Published var channel: DiscoverChannel
    @Published private(set) var newsItems: [NewsItem] = []
    @Published private(set) var newsState: DiscoverLoadState = .idle
    @Published private(set) var newsUpdatedAt: String?
    @Published private(set) var newsSources: [String] = []

    @Published var gameSection: GameSection = .news
    @Published private(set) var rankItems: [GameRankItem] = []
    @Published private(set) var rankState: DiscoverLoadState = .idle
    @Published private(set) var rankUpdatedAt: String?
    @Published private(set) var rankSource: String = ""

    @Published private(set) var indexes: [StockQuote] = []
    @Published private(set) var watchQuotes: [StockQuote] = []
    @Published private(set) var marketState: DiscoverLoadState = .idle
    @Published private(set) var marketUpdatedAt: String?
    @Published private(set) var marketSource: String = ""
    @Published private(set) var watchlist: [String]

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [StockSearchResult] = []
    @Published private(set) var searchState: DiscoverLoadState = .idle

    init(initialChannel: DiscoverChannel = .ai) {
        channel = initialChannel
        watchlist = store.symbols
        watchlistCancellable = store.$symbols.sink { [weak self] symbols in
            guard let self, symbols != self.watchlist else { return }
            self.watchlist = symbols
            if self.channel == .market {
                Task { await self.loadMarket(force: true) }
            }
        }
    }

    func loadInitial() async {
        if channel == .market {
            await loadMarket(force: false)
        } else if channel == .game, let board = gameSection.board {
            await loadRank(board, force: false)
        } else {
            await loadNews(channel: channel, force: false)
        }
    }

    func select(_ next: DiscoverChannel) async {
        withAnimation(.snappy(duration: 0.24)) { channel = next }
        if next == .market {
            await loadMarket(force: false)
        } else if next == .game, let board = gameSection.board {
            await loadRank(board, force: false)
        } else {
            await loadNews(channel: next, force: false)
        }
    }

    func selectGameSection(_ next: GameSection) async {
        withAnimation(.snappy(duration: 0.22)) { gameSection = next }
        if let board = next.board {
            await loadRank(board, force: false)
        } else {
            await loadNews(channel: .game, force: false)
        }
    }

    func refresh() async {
        if channel == .market {
            await loadMarket(force: true)
        } else if channel == .game, let board = gameSection.board {
            await loadRank(board, force: true)
        } else {
            await loadNews(channel: channel, force: true)
        }
    }

    func loadRank(_ board: GameRankBoard, force: Bool) async {
        if !force, loadedRankBoard == board, rankState == .loaded { return }
        if let cached = rankCache[board] {
            if Date().timeIntervalSince(cached.at) < 300, !force {
                apply(cached.response, board: board)
                rankState = .loaded
                return
            }
            apply(cached.response, board: board)
        } else if loadedRankBoard != board {
            rankItems = []
            rankUpdatedAt = nil
            rankSource = ""
        }
        if rankItems.isEmpty { rankState = .loading }
        let token = UUID()
        requestToken = token
        do {
            let response = try await client.gameRank(board: board, limit: 50)
            guard requestToken == token, channel == .game, gameSection.board == board else { return }
            rankCache[board] = (response, Date())
            apply(response, board: board)
            rankState = .loaded
        } catch {
            guard requestToken == token, channel == .game, gameSection.board == board else { return }
            if rankItems.isEmpty {
                rankState = .failed(message(error))
            } else {
                rankState = .loaded
            }
        }
    }

    func loadNews(channel: DiscoverChannel, force: Bool) async {
        guard channel != .market else { return }
        let token = UUID()
        requestToken = token
        if let cached = newsCache[channel] {
            if Date().timeIntervalSince(cached.at) < 300, !force {
                apply(cached.response, channel: channel)
                newsState = .loaded
                return
            }
            apply(cached.response, channel: channel)
        } else if loadedNewsChannel != channel {
            newsItems = []
            newsUpdatedAt = nil
            newsSources = []
        }
        if newsItems.isEmpty { newsState = .loading }
        do {
            let response = try await client.news(channel: channel, limit: 24)
            guard requestToken == token, self.channel == channel else { return }
            newsCache[channel] = (response, Date())
            apply(response, channel: channel)
            newsState = .loaded
        } catch {
            guard requestToken == token, self.channel == channel else { return }
            if newsItems.isEmpty {
                newsState = .failed(message(error))
            } else {
                newsState = .loaded
            }
        }
    }

    func loadMarket(force: Bool) async {
        if watchlist.isEmpty && marketState == .loaded && !force { return }
        if indexes.isEmpty && watchQuotes.isEmpty { marketState = .loading }
        var messages: [String] = []

        do {
            let response = try await client.indexes()
            indexes = response.quotes
            marketUpdatedAt = response.updatedAt
            marketSource = response.source
        } catch {
            messages.append(message(error))
        }

        if !watchlist.isEmpty {
            do {
                let response = try await client.quotes(symbols: watchlist)
                watchQuotes = response.quotes
                marketUpdatedAt = response.updatedAt
                marketSource = response.source
            } catch {
                messages.append(message(error))
            }
        } else {
            watchQuotes = []
        }

        if indexes.isEmpty && watchQuotes.isEmpty, let first = messages.first {
            marketState = .failed(first)
        } else {
            marketState = .loaded
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let text = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searchResults = []
            searchState = .idle
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(text)
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        searchState = .idle
    }

    func addToWatchlist(_ symbol: String) {
        guard store.add(symbol) else { return }
        Task { await loadMarket(force: true) }
    }

    func removeFromWatchlist(_ symbol: String) {
        guard store.remove(symbol) else { return }
        watchQuotes.removeAll { $0.symbol == symbol.lowercased() }
        Task { await loadMarket(force: true) }
    }

    func isWatched(_ symbol: String) -> Bool {
        watchlist.contains(symbol.lowercased())
    }

    func quote(for symbol: String) -> StockQuote? {
        (watchQuotes + indexes).first { $0.symbol == symbol.lowercased() }
    }

    private func runSearch(_ text: String) async {
        searchState = .loading
        do {
            let response = try await client.search(text)
            guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            searchResults = response.results
            searchState = response.results.isEmpty ? .failed("没有找到「\(text)」匹配的 A 股或指数") : .loaded
        } catch {
            searchResults = []
            searchState = .failed(message(error))
        }
    }

    private func apply(_ response: NewsFeedResponse, channel: DiscoverChannel) {
        newsItems = response.items
        newsUpdatedAt = response.updatedAt
        newsSources = response.sources ?? []
        loadedNewsChannel = channel
    }

    private func apply(_ response: GameRankResponse, board: GameRankBoard) {
        rankItems = response.items
        rankUpdatedAt = response.updatedAt
        rankSource = response.source
        loadedRankBoard = board
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

@MainActor
final class StockDetailModel: ObservableObject {
    let quote: StockQuote
    let client = DiscoverClient()

    @Published private(set) var current: StockQuote
    @Published private(set) var intraday: [IntradayPoint] = []
    @Published private(set) var kline: [KlinePoint] = []
    @Published private(set) var state: DiscoverLoadState = .idle
    @Published private(set) var chartState: DiscoverLoadState = .idle
    @Published private(set) var updatedAt: String?
    @Published private(set) var source: String = ""

    init(quote: StockQuote) {
        self.quote = quote
        current = quote
    }

    func load() async {
        if state == .idle { state = .loading }
        if chartState == .idle { chartState = .loading }
        do {
            let response = try await client.quotes(symbols: [quote.symbol])
            if let next = response.quotes.first {
                current = next
                updatedAt = response.updatedAt
                source = next.source ?? response.source
            }
            state = .loaded
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        async let intradayResult = try? client.intraday(symbol: quote.symbol)
        async let klineResult = try? client.kline(symbol: quote.symbol, days: 160)
        let (intradayResponse, klineResponse) = await (intradayResult, klineResult)
        if let intradayResponse {
            intraday = intradayResponse.points
        }
        if let klineResponse {
            kline = klineResponse.points
        }
        chartState = intraday.isEmpty && kline.isEmpty ? .failed("分时与日线暂时没有取到") : .loaded
    }
}

import Combine
import Foundation
import SwiftUI

@MainActor
final class DiscoverModel: ObservableObject {
    let client = DiscoverClient()
    private let store = WatchlistStore.shared
    private let defaults = UserDefaults.standard
    private static let aiSectionKey = "whale.discover.aiSection"
    private static let headlineSectionKey = "whale.discover.headlineSection"
    private static let gameNewsSectionKey = "whale.discover.gameNewsSection"
    private static let paperCategoryKey = "whale.discover.paperCategory"
    private static let gameSectionKey = "whale.discover.gameSection"
    private var newsCache: [DiscoverChannel: (response: NewsFeedResponse, at: Date)] = [:]
    private var rankCache: [GameRankBoard: (response: GameRankResponse, at: Date)] = [:]
    private var hotCache: (response: WeiboHotResponse, at: Date)?
    private var paperCache: [AIPaperCategory: (response: AIPaperFeedResponse, at: Date)] = [:]
    private var steamCache: (response: SteamFeaturedResponse, at: Date)?
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

    @Published private(set) var papers: [AIPaper] = []
    @Published private(set) var papersState: DiscoverLoadState = .idle
    @Published private(set) var papersUpdatedAt: String?
    @Published private(set) var papersSource: String = ""
    @Published private(set) var paperCategory: AIPaperCategory = .ai {
        didSet { defaults.set(paperCategory.rawValue, forKey: Self.paperCategoryKey) }
    }

    @Published var gameSection: GameSection = .news {
        didSet { defaults.set(gameSection.rawValue, forKey: Self.gameSectionKey) }
    }
    @Published private(set) var rankItems: [GameRankItem] = []
    @Published private(set) var rankState: DiscoverLoadState = .idle
    @Published private(set) var rankUpdatedAt: String?
    @Published private(set) var rankSource: String = ""

    @Published var aiSection: String = "all" {
        didSet { defaults.set(aiSection, forKey: Self.aiSectionKey) }
    }
    @Published var headlineSection: String = "all" {
        didSet { defaults.set(headlineSection, forKey: Self.headlineSectionKey) }
    }
    @Published var gameNewsSection: String = "all" {
        didSet { defaults.set(gameNewsSection, forKey: Self.gameNewsSectionKey) }
    }

    @Published private(set) var steam: SteamFeaturedResponse?
    @Published private(set) var steamState: DiscoverLoadState = .idle

    @Published private(set) var hotItems: [WeiboHotItem] = []
    @Published private(set) var hotState: DiscoverLoadState = .idle
    @Published private(set) var hotUpdatedAt: String?
    @Published private(set) var hotSource: String = ""
    @Published private(set) var hotNote: String = ""

    @Published private(set) var indexes: [StockQuote] = []
    @Published private(set) var watchQuotes: [StockQuote] = []
    @Published private(set) var marketState: DiscoverLoadState = .idle
    @Published private(set) var marketUpdatedAt: String?
    @Published private(set) var marketSource: String = ""
    @Published private(set) var watchlist: [String]
    @Published private(set) var watchFlows: [String: FundFlowPoint] = [:]

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [StockSearchResult] = []
    @Published private(set) var searchState: DiscoverLoadState = .idle

    init(initialChannel: DiscoverChannel = .ai) {
        channel = initialChannel
        watchlist = store.symbols
        let saved = UserDefaults.standard
        aiSection = saved.string(forKey: Self.aiSectionKey) ?? "all"
        headlineSection = saved.string(forKey: Self.headlineSectionKey) ?? "all"
        gameNewsSection = saved.string(forKey: Self.gameNewsSectionKey) ?? "all"
        paperCategory = AIPaperCategory(rawValue: saved.string(forKey: Self.paperCategoryKey) ?? "") ?? .ai
        gameSection = GameSection(rawValue: saved.string(forKey: Self.gameSectionKey) ?? "") ?? .news
        watchlistCancellable = store.$symbols.sink { [weak self] symbols in
            guard let self, symbols != self.watchlist else { return }
            self.watchlist = symbols
            if self.channel == .market {
                Task { await self.loadMarket(force: true) }
            }
        }
    }

    var aiNews: [NewsItem] {
        newsItems.filter { DiscoverChannel.ai.matches(section: aiSection, itemSection: $0.section) }
    }

    var headlineNews: [NewsItem] {
        newsItems.filter { DiscoverChannel.headline.matches(section: headlineSection, itemSection: $0.section) }
    }

    var gameNews: [NewsItem] {
        newsItems.filter { DiscoverChannel.game.matches(section: gameNewsSection, itemSection: $0.section) }
    }

    func selectNewsSection(_ section: String, for channel: DiscoverChannel) async {
        applyNewsSection(section, for: channel)
    }

    func stepNewsSection(_ channel: DiscoverChannel, by delta: Int) {
        let sections = channel.newsSections
        let current: String
        switch channel {
        case .ai: current = aiSection
        case .headline: current = headlineSection
        case .game: current = gameNewsSection
        default: return
        }
        guard let index = sections.firstIndex(where: { $0.id == current }) else { return }
        let next = min(max(index + delta, 0), sections.count - 1)
        guard next != index else { return }
        applyNewsSection(sections[next].id, for: channel)
    }

    func stepGameSection(by delta: Int) async {
        let sections = GameSection.allCases
        guard let index = sections.firstIndex(of: gameSection) else { return }
        let next = min(max(index + delta, 0), sections.count - 1)
        guard next != index else { return }
        await selectGameSection(sections[next])
    }

    func stepPaperCategory(by delta: Int) async {
        let categories = AIPaperCategory.allCases
        guard let index = categories.firstIndex(of: paperCategory) else { return }
        let next = min(max(index + delta, 0), categories.count - 1)
        guard next != index else { return }
        await selectPaperCategory(categories[next])
    }

    private func applyNewsSection(_ section: String, for channel: DiscoverChannel) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch channel {
            case .ai: aiSection = section
            case .headline: headlineSection = section
            case .game: gameNewsSection = section
            default: return
            }
        }
    }

    func loadInitial() async {
        if channel == .market {
            await loadMarket(force: false)
        } else if channel == .game {
            await loadGameSection(gameSection, force: false)
        } else if channel == .weibo {
            await loadWeiboHot(force: false)
        } else if channel == .ai {
            await loadNews(channel: .ai, force: false)
            await loadPapers(category: paperCategory, force: false)
        } else if channel == .headline || channel == .game {
            await loadNews(channel: channel, force: false)
        }
    }

    func select(_ next: DiscoverChannel) async {
        withAnimation(.snappy(duration: 0.24)) { channel = next }
        if next == .market {
            await loadMarket(force: false)
        } else if next == .game {
            await loadGameSection(gameSection, force: false)
        } else if next == .weibo {
            await loadWeiboHot(force: false)
        } else if next == .ai {
            await loadNews(channel: .ai, force: false)
            await loadPapers(category: paperCategory, force: false)
        } else if next == .headline || next == .game {
            await loadNews(channel: next, force: false)
        }
    }

    func selectGameSection(_ next: GameSection) async {
        withAnimation(.snappy(duration: 0.22)) { gameSection = next }
        await loadGameSection(next, force: false)
    }

    private func loadGameSection(_ section: GameSection, force: Bool) async {
        if let board = section.board {
            await loadRank(board, force: force)
        } else if let kind = section.steamKind {
            await loadSteam(kind: kind, force: force)
        } else {
            await loadNews(channel: .game, force: force)
        }
    }

    func loadSteam(kind: SteamKind, force: Bool) async {
        if !force, let cached = steamCache, Date().timeIntervalSince(cached.at) < 300, steamState == .loaded, steam != nil {
            return
        }
        if let cached = steamCache {
            steam = cached.response
        }
        if steam == nil { steamState = .loading }
        do {
            let response = try await client.steamFeatured()
            steamCache = (response, Date())
            steam = response
            steamState = .loaded
        } catch {
            steamState = steam == nil ? .failed(message(error)) : .loaded
        }
    }

    func steamItems(kind: SteamKind) -> [SteamItem] {
        steam?.items(for: kind) ?? []
    }

    func refresh() async {
        if channel == .market {
            await loadMarket(force: true)
        } else if channel == .game {
            await loadGameSection(gameSection, force: true)
        } else if channel == .weibo {
            await loadWeiboHot(force: true)
        } else if channel == .ai {
            await loadNews(channel: .ai, force: true)
            await loadPapers(category: paperCategory, force: true)
        } else if channel == .headline || channel == .game {
            await loadNews(channel: channel, force: true)
        }
    }

    func loadPapers(category: AIPaperCategory, force: Bool) async {
        if !force, let cached = paperCache[category], Date().timeIntervalSince(cached.at) < 600, papersState == .loaded, paperCategory == category {
            apply(cached.response)
            return
        }
        if let cached = paperCache[category] {
            apply(cached.response)
        } else if paperCategory != category {
            papers = []
            papersUpdatedAt = nil
            papersSource = ""
        }
        paperCategory = category
        if papers.isEmpty { papersState = .loading }
        let token = UUID()
        requestToken = token
        do {
            let response = try await client.aiPapers(category: category, limit: 6)
            guard requestToken == token, channel == .ai, paperCategory == category else { return }
            paperCache[category] = (response, Date())
            apply(response)
            papersState = .loaded
        } catch {
            guard requestToken == token, channel == .ai, paperCategory == category else { return }
            papersState = papers.isEmpty ? .failed(message(error)) : .loaded
        }
    }

    func selectPaperCategory(_ next: AIPaperCategory) async {
        guard next != paperCategory else { return }
        paperCategory = next
        papers = []
        papersState = .idle
        await loadPapers(category: next, force: false)
    }

    func loadWeiboHot(force: Bool) async {
        if !force, let cached = hotCache, Date().timeIntervalSince(cached.at) < 180, hotState == .loaded {
            apply(cached.response)
            return
        }
        if let cached = hotCache {
            apply(cached.response)
        }
        if hotItems.isEmpty { hotState = .loading }
        let token = UUID()
        requestToken = token
        do {
            let response = try await client.weiboHot(limit: 50)
            guard requestToken == token, channel == .weibo else { return }
            hotCache = (response, Date())
            apply(response)
            hotState = .loaded
        } catch {
            guard requestToken == token, channel == .weibo else { return }
            if hotItems.isEmpty {
                hotState = .failed(message(error))
            } else {
                hotState = .loaded
            }
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
        guard channel == .ai || channel == .headline || channel == .game else { return }
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
            let response = try await client.news(channel: channel, limit: 40)
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
                watchFlows = await client.todayFundFlows(symbols: watchlist)
            } catch {
                messages.append(message(error))
                watchFlows = [:]
            }
        } else {
            watchQuotes = []
            watchFlows = [:]
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

    private func apply(_ response: WeiboHotResponse) {
        hotItems = response.items
        hotUpdatedAt = response.updatedAt
        hotSource = response.source
        hotNote = response.note
    }

    private func apply(_ response: AIPaperFeedResponse) {
        papers = response.papers
        papersUpdatedAt = response.updatedAt
        papersSource = response.source
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
    @Published private(set) var fundFlow: [FundFlowPoint] = []
    @Published private(set) var fundFlowState: DiscoverLoadState = .idle
    @Published private(set) var fundFlowSource: String = ""
    @Published private(set) var updatedAt: String?
    @Published private(set) var source: String = ""

    init(quote: StockQuote) {
        self.quote = quote
        current = quote
    }

    func load() async {
        if state == .idle { state = .loading }
        if chartState == .idle { chartState = .loading }
        if fundFlowState == .idle { fundFlowState = .loading }
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
        async let flowResult = try? client.fundFlow(symbol: quote.symbol, days: 6)
        let (intradayResponse, klineResponse, flowResponse) = await (intradayResult, klineResult, flowResult)
        if let intradayResponse {
            intraday = intradayResponse.points
        }
        if let klineResponse {
            kline = klineResponse.points
        }
        chartState = intraday.isEmpty && kline.isEmpty ? .failed("分时与日线暂时没有取到") : .loaded
        if let flowResponse {
            fundFlow = flowResponse.points
            fundFlowSource = flowResponse.source
            fundFlowState = .loaded
        } else {
            fundFlowState = .failed("资金流暂时没有取到，稍后下拉重试")
        }
    }
}

@MainActor
final class GameDetailModel: ObservableObject {
    let item: GameRankItem
    private let client = DiscoverClient()

    @Published private(set) var detail: AppStoreAppDetail?
    @Published private(set) var state: DiscoverLoadState = .idle

    init(item: GameRankItem) {
        self.item = item
    }

    func load() async {
        if state == .idle { state = .loading }
        do {
            let response = try await client.appStoreLookup(id: item.id)
            detail = response
            state = .loaded
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

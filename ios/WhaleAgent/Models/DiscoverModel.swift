import Combine
import Foundation
import SwiftUI

@MainActor
final class DiscoverModel: ObservableObject {
    let client: DiscoverClient
    private let marketProvider: any MarketDataProvider
    private let store: WatchlistStore
    private let defaults = UserDefaults.standard
    private static let aiSectionKey = "whale.discover.aiSection"
    private static let headlineSectionKey = "whale.discover.headlineSection"
    private static let gameNewsSectionKey = "whale.discover.gameNewsSection"
    private static let paperCategoryKey = "whale.discover.paperCategory"
    private static let gameSectionKey = "whale.discover.gameSection"
    private static let hotBoardKey = "whale.discover.hotBoard"
    private var newsCache: [DiscoverChannel: (response: NewsFeedResponse, at: Date)] = [:]
    private var rankCache: [GameRankBoard: (response: GameRankResponse, at: Date)] = [:]
    private var hotCaches: [HotBoard: (response: WeiboHotResponse, at: Date)] = [:]
    private var paperCache: [AIPaperCategory: (response: AIPaperFeedResponse, at: Date)] = [:]
    private var steamCache: (response: SteamFeaturedResponse, at: Date)?
    private var loadedNewsChannel: DiscoverChannel?
    private var loadedRankBoard: GameRankBoard?
    private var loadedHotBoard: HotBoard?
    private var searchTask: Task<Void, Never>?
    private var requestToken = UUID()
    private var searchToken = UUID()
    private var marketToken = UUID()
    @Published private(set) var indexesUpdatedAt: String?
    @Published private(set) var watchUpdatedAt: String?
    @Published private(set) var cacheWarning: String?
    private var cacheObserver: AnyCancellable?
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
    @Published var hotBoard: HotBoard = .weibo {
        didSet { defaults.set(hotBoard.rawValue, forKey: Self.hotBoardKey) }
    }

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

    init(initialChannel: DiscoverChannel = .ai, marketProvider: (any MarketDataProvider)? = nil,
         watchlistStore: WatchlistStore? = nil) {
        let contentClient = DiscoverClient()
        client = contentClient
        self.marketProvider = marketProvider ?? contentClient
        let selectedStore = watchlistStore ?? WatchlistStore.shared
        store = selectedStore
        channel = initialChannel
        watchlist = selectedStore.symbols
        let saved = UserDefaults.standard
        // These channels are unified feeds. Old saved filters must not hide
        // articles after their category controls have been removed.
        aiSection = "all"
        headlineSection = "all"
        saved.removeObject(forKey: Self.aiSectionKey)
        saved.removeObject(forKey: Self.headlineSectionKey)
        gameNewsSection = saved.string(forKey: Self.gameNewsSectionKey) ?? "all"
        paperCategory = AIPaperCategory(rawValue: saved.string(forKey: Self.paperCategoryKey) ?? "") ?? .ai
        hotBoard = HotBoard(rawValue: saved.string(forKey: Self.hotBoardKey) ?? "") ?? .weibo
        gameSection = GameSection(rawValue: saved.string(forKey: Self.gameSectionKey) ?? "") ?? .news
        hydrateFromDisk()
        cacheObserver = NotificationCenter.default.publisher(for: .whaleCacheWriteFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cacheWarning = "本次数据已显示，但离线缓存未保存；下次启动需要联网。" }
        watchlistCancellable = store.$symbols.sink { [weak self] symbols in
            guard let self, symbols != self.watchlist else { return }
            self.marketToken = UUID()
            self.watchlist = symbols
            self.watchQuotes.removeAll { !symbols.contains($0.symbol) }
            self.watchFlows = self.watchFlows.filter { symbols.contains($0.key) }
            if self.channel == .market {
                Task { await self.loadMarket(force: true) }
            }
        }
    }

    var dataNotice: String? {
        if let cacheWarning { return cacheWarning }
        switch channel {
        case .ai, .headline: return newsState.notice
        case .market: return marketState.notice
        case .game: return (gameSection.board != nil ? rankState : gameSection.steamKind != nil ? steamState : newsState).notice
        case .weibo: return hotState.notice
        case .music: return nil
        }
    }

    var aiNews: [NewsItem] {
        newsItems.filter { item in
            // 旧缓存可能残留英文标题或只有标题的条目，展示层再兜底一次。
            guard item.displaySummary.count >= 10 else { return false }
            return item.displayTitle.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        }
    }

    var headlineNews: [NewsItem] {
        newsItems
    }

    var gameNews: [NewsItem] {
        newsItems.filter { DiscoverChannel.game.matches(section: gameNewsSection, itemSection: $0.section, topics: $0.topics) }
    }

    func selectNewsSection(_ section: String, for channel: DiscoverChannel) async {
        applyNewsSection(section, for: channel)
    }

    func stepNewsSection(_ channel: DiscoverChannel, by delta: Int) {
        guard channel == .game else { return }
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
        // 旧版本可能保存过已下线的标签（例如“视频生成”），统一回落到“全部”。
        let validSection = channel == .game && channel.newsSections.contains { $0.id == section } ? section : "all"
        withAnimation(.easeInOut(duration: 0.18)) {
            switch channel {
            case .ai: aiSection = validSection
            case .headline: headlineSection = validSection
            case .game: gameNewsSection = validSection
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
            await loadHot(force: false)
        } else if channel == .ai {
            await loadNews(channel: .ai, force: false)
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
            await loadHot(force: false)
        } else if next == .ai {
            await loadNews(channel: .ai, force: false)
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
        let token = UUID()
        requestToken = token
        if !force, let cached = steamCache, Date().timeIntervalSince(cached.at) < 300, steamState == .loaded, steam != nil {
            return
        }
        if let cached = steamCache {
            steam = cached.response
        }
        if steam == nil { steamState = .loading }
        do {
            let response = try await client.steamFeatured()
            guard requestToken == token, channel == .game, gameSection.steamKind == kind else { return }
            steamCache = (response, Date())
            DiscoverDiskCache.save(response, key: "steam")
            steam = response
            steamState = .loaded
        } catch {
            guard requestToken == token, channel == .game, gameSection.steamKind == kind else { return }
            steamState = steam == nil ? .failed(message(error)) : .stale(message(error))
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
            await loadHot(force: true)
        } else if channel == .ai {
            await loadNews(channel: .ai, force: true)
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
            DiscoverDiskCache.save(response, key: "papers-\(category.rawValue)")
            apply(response)
            papersState = .loaded
        } catch {
            guard requestToken == token, channel == .ai, paperCategory == category else { return }
            papersState = papers.isEmpty ? .failed(message(error)) : .stale(message(error))
        }
    }

    func selectPaperCategory(_ next: AIPaperCategory) async {
        guard next != paperCategory else { return }
        paperCategory = next
        papers = []
        papersState = .idle
        await loadPapers(category: next, force: false)
    }

    func loadHot(force: Bool) async {
        await loadHot(board: hotBoard, force: force)
    }

    func selectHotBoard(_ next: HotBoard) async {
        guard next != hotBoard else { return }
        withAnimation(.snappy(duration: 0.22)) { hotBoard = next }
        await loadHot(board: next, force: false)
    }

    func stepHotBoard(by delta: Int) {
        let all = HotBoard.allCases
        guard let index = all.firstIndex(of: hotBoard) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        guard next != index else { return }
        Task { await selectHotBoard(all[next]) }
    }

    private func loadHot(board: HotBoard, force: Bool) async {
        if loadedHotBoard != board {
            if let cached = hotCaches[board] {
                apply(cached.response)
            } else {
                hotItems = []
                hotUpdatedAt = nil
                hotSource = ""
                hotNote = ""
                hotState = .idle
            }
            loadedHotBoard = board
        }
        if !force, let cached = hotCaches[board], Date().timeIntervalSince(cached.at) < 180, hotState == .loaded {
            apply(cached.response)
            return
        }
        if let cached = hotCaches[board] {
            apply(cached.response)
        }
        if hotItems.isEmpty { hotState = .loading }
        let token = UUID()
        requestToken = token
        do {
            let response: WeiboHotResponse
            switch board {
            case .weibo: response = try await client.weiboHot(limit: 50)
            case .zhihu: response = try await client.zhihuHot(limit: 50)
            }
            guard requestToken == token, channel == .weibo, hotBoard == board else { return }
            hotCaches[board] = (response, Date())
            DiscoverDiskCache.save(response, key: hotDiskKey(board))
            apply(response)
            hotState = .loaded
        } catch {
            guard requestToken == token, channel == .weibo, hotBoard == board else { return }
            if hotItems.isEmpty {
                hotState = .failed(message(error))
            } else {
                hotState = .stale(message(error))
            }
        }
    }

    func loadRank(_ board: GameRankBoard, force: Bool) async {
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
            let response = try await client.gameRank(board: board, limit: 50, force: force)
            guard requestToken == token, channel == .game, gameSection.board == board else { return }
            rankCache[board] = (response, Date())
            DiscoverDiskCache.save(response, key: "rank-\(board.rawValue)")
            apply(response, board: board)
            rankState = .loaded
        } catch {
            guard requestToken == token, channel == .game, gameSection.board == board else { return }
            if rankItems.isEmpty {
                rankState = .failed(message(error))
            } else {
                rankState = .stale(message(error))
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
            let response = try await client.news(channel: channel, limit: 40, force: force)
            guard requestToken == token, self.channel == channel else { return }
            newsCache[channel] = (response, DiscoverFormat.date(from: response.updatedAt) ?? .distantPast)
            DiscoverDiskCache.save(response, key: newsDiskKey(channel))
            apply(response, channel: channel)
            newsState = (response.unavailableSources ?? []).isEmpty ? .loaded : .partial((response.unavailableSources ?? []).joined(separator: "、"))
        } catch {
            guard requestToken == token, self.channel == channel else { return }
            if newsItems.isEmpty {
                newsState = .failed(message(error))
            } else {
                newsState = .stale(message(error))
            }
        }
    }

    func loadMarket(force: Bool) async {
        let token = UUID()
        marketToken = token
        let symbols = watchlist
        if indexes.isEmpty && watchQuotes.isEmpty { marketState = .loading }
        var messages: [String] = []
        do {
            let response = try await marketProvider.indexes(force: force)
            guard marketToken == token else { return }
            indexes = response.quotes
            indexesUpdatedAt = response.updatedAt
            marketSource = response.source
            messages += (response.errors ?? []).map(\.message)
        } catch {
            guard marketToken == token else { return }
            messages.append(message(error))
        }
        if !symbols.isEmpty {
            do {
                let response = try await marketProvider.quotes(symbols: symbols, force: force)
                guard marketToken == token, watchlist == symbols else { return }
                watchQuotes = response.quotes.filter { watchlist.contains($0.symbol) }
                watchUpdatedAt = response.updatedAt
                marketSource = response.source
                messages += (response.errors ?? []).map(\.message)
                let flows = await marketProvider.todayFundFlows(symbols: symbols)
                guard marketToken == token, watchlist == symbols else { return }
                watchFlows = flows.filter { watchlist.contains($0.key) }
            } catch {
                guard marketToken == token, watchlist == symbols else { return }
                messages.append(message(error))
            }
        } else {
            watchQuotes = []
            watchFlows = [:]
            watchUpdatedAt = nil
        }
        guard marketToken == token else { return }
        let dates = [indexesUpdatedAt, symbols.isEmpty ? nil : watchUpdatedAt].compactMap { $0 }.compactMap(DiscoverFormat.date)
        marketUpdatedAt = dates.min().map(ToolDate.iso)
        if !messages.isEmpty {
            marketState = indexes.isEmpty && watchQuotes.isEmpty ? .failed(messages.joined(separator: "；")) : .partial(messages.joined(separator: "；"))
        } else { marketState = .loaded }
    }

    func scheduleSearch() {
        searchToken = UUID()
        searchTask?.cancel()
        let token = searchToken
        let text = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searchResults = []
            searchState = .idle
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(text, token: token)
        }
    }

    func clearSearch() {
        searchToken = UUID()
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        searchState = .idle
    }

    func searchNow() async {
        searchTask?.cancel()
        searchToken = UUID()
        let text = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { clearSearch(); return }
        await runSearch(text, token: searchToken)
    }

    func addToWatchlist(_ symbol: String) {
        guard store.add(symbol) else { return }
    }

    func removeFromWatchlist(_ symbol: String) {
        guard store.remove(symbol) else { return }
        watchQuotes.removeAll { $0.symbol == symbol.lowercased() }
    }

    func isWatched(_ symbol: String) -> Bool {
        watchlist.contains(symbol.lowercased())
    }

    func quote(for symbol: String) -> StockQuote? {
        (watchQuotes + indexes).first { $0.symbol == symbol.lowercased() }
    }

    private func runSearch(_ text: String, token: UUID) async {
        guard searchToken == token, !Task.isCancelled else { return }
        searchState = .loading
        do {
            let response = try await marketProvider.search(text)
            guard searchToken == token, !Task.isCancelled, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            searchResults = response.results
            searchState = response.results.isEmpty ? .failed("没有找到「\(text)」匹配的 A 股或指数") : .loaded
        } catch {
            guard searchToken == token, !Task.isCancelled, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            searchResults = []
            searchState = .failed(message(error))
        }
    }

    private func hydrateFromDisk() {
        for item in [DiscoverChannel.ai, .headline, .game] {
            guard let cached = DiscoverDiskCache.load(NewsFeedResponse.self, key: newsDiskKey(item)) else { continue }
            newsCache[item] = (cached, .distantPast)
        }
        for board in GameRankBoard.allCases {
            guard let cached = DiscoverDiskCache.load(GameRankResponse.self, key: "rank-\(board.rawValue)") else { continue }
            rankCache[board] = (cached, .distantPast)
        }
        if let cached = DiscoverDiskCache.load(WeiboHotResponse.self, key: "weibo") {
            hotCaches[.weibo] = (cached, .distantPast)
        }
        if let cached = DiscoverDiskCache.load(WeiboHotResponse.self, key: "zhihu") {
            hotCaches[.zhihu] = (cached, .distantPast)
        }
        if let cached = DiscoverDiskCache.load(SteamFeaturedResponse.self, key: "steam") {
            steamCache = (cached, .distantPast)
        }

        switch channel {
        case .ai:
            if let cached = newsCache[.ai] {
                apply(cached.response, channel: .ai)
                newsState = .cached
            }
        case .headline:
            if let cached = newsCache[.headline] {
                apply(cached.response, channel: .headline)
                newsState = .cached
            }
        case .game:
            if let board = gameSection.board, let cached = rankCache[board] {
                apply(cached.response, board: board)
                rankState = .cached
            } else if gameSection.steamKind != nil, let cached = steamCache {
                steam = cached.response
                steamState = .cached
            } else if let cached = newsCache[.game] {
                apply(cached.response, channel: .game)
                newsState = .cached
            }
        case .weibo:
            if let cached = hotCaches[hotBoard] {
                apply(cached.response)
                loadedHotBoard = hotBoard
                hotState = .cached
            }
        case .market, .music:
            break
        }
    }

    private func newsDiskKey(_ channel: DiscoverChannel) -> String {
        channel == .ai ? "news-ai-topics-v4" : "news-\(channel.rawValue)"
    }

    private func hotDiskKey(_ board: HotBoard) -> String {
        board == .weibo ? "weibo" : "zhihu"
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
    @Published private(set) var profile: StockProfile?
    @Published private(set) var profileState: DiscoverLoadState = .idle
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
        if profileState == .idle { profileState = .loading }
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
        async let profileResult = try? client.stockProfile(symbol: quote.symbol)
        let (intradayResponse, klineResponse, flowResponse, profileResponse) = await (intradayResult, klineResult, flowResult, profileResult)
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
        if let profileResponse {
            profile = profileResponse
            profileState = .loaded
        } else {
            profileState = .failed("证券资料暂时没有取到，稍后下拉重试")
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

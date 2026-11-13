import Foundation

enum DiscoverChannel: String, CaseIterable, Identifiable, Hashable {
    case ai
    case market
    case game
    case music
    case headline
    case weibo

    var id: String { rawValue }

    var tabTitle: String {
        switch self {
        case .ai: return "AI科技"
        case .market: return "A股"
        case .game: return "游戏"
        case .music: return "音乐"
        case .headline: return "新闻"
        case .weibo: return "热榜"
        }
    }

    var title: String {
        switch self {
        case .ai: return "AI科技"
        case .market: return "A股自选"
        case .game: return "游戏动态"
        case .music: return "我的音乐"
        case .headline: return "时事新闻"
        case .weibo: return "热榜"
        }
    }

    var subtitle: String {
        switch self {
        case .ai: return "游戏应用 · 程序开发 · 游戏科技"
        case .market: return "指数 · 自选 · 详情资料 · 资金动向"
        case .game: return "游戏媒体资讯 · App Store 榜单"
        case .music: return "系统资料库 · 本地音乐 · 播放控制"
        case .headline: return "要闻 · 权威媒体 RSS"
        case .weibo: return "微博热搜 · 知乎热榜"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .market: return "chart.line.uptrend.xyaxis"
        case .game: return "gamecontroller.fill"
        case .music: return "music.note"
        case .headline: return "newspaper.fill"
        case .weibo: return "flame.fill"
        }
    }
}

enum HotBoard: String, CaseIterable, Identifiable, Hashable {
    case weibo
    case zhihu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weibo: return "微博热搜"
        case .zhihu: return "知乎热榜"
        }
    }

    var subtitle: String {
        switch self {
        case .weibo: return "实时热搜 · 公开数据"
        case .zhihu: return "热门讨论 · 公开数据"
        }
    }

    var icon: String {
        switch self {
        case .weibo: return "flame.fill"
        case .zhihu: return "text.bubble.fill"
        }
    }
}

enum AIPaperCategory: String, CaseIterable, Identifiable, Hashable {
    case ai = "cs.AI"
    case machineLearning = "cs.LG"
    case language = "cs.CL"
    case vision = "cs.CV"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "人工智能"
        case .machineLearning: return "机器学习"
        case .language: return "自然语言"
        case .vision: return "计算机视觉"
        }
    }
}

enum GameSection: String, CaseIterable, Identifiable, Hashable {
    case news
    case steamTop
    case steamDeals
    case comingSoon
    case free
    case grossing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: return "游戏资讯"
        case .steamTop: return "Steam畅销"
        case .steamDeals: return "Steam折扣"
        case .comingSoon: return "新作预告"
        case .free: return "免费榜"
        case .grossing: return "畅销榜"
        }
    }

    var board: GameRankBoard? {
        switch self {
        case .news, .steamTop, .steamDeals, .comingSoon: return nil
        case .free: return .free
        case .grossing: return .grossing
        }
    }

    var steamKind: SteamKind? {
        switch self {
        case .steamTop: return .topSellers
        case .steamDeals: return .specials
        case .comingSoon: return .comingSoon
        case .news, .free, .grossing: return nil
        }
    }
}

enum SteamKind: String, Identifiable, Hashable {
    case topSellers
    case specials
    case comingSoon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topSellers: return "Steam 全球畅销"
        case .specials: return "Steam 折扣特惠"
        case .comingSoon: return "即将发售与新作预告"
        }
    }

    var subtitle: String {
        switch self {
        case .topSellers: return "Steam 商店中国区 · 实时畅销顺序"
        case .specials: return "Steam 商店中国区 · 折扣与价格实时变动"
        case .comingSoon: return "Steam 商店中国区 · 即将发售作品"
        }
    }
}

enum GameRankBoard: String, CaseIterable, Identifiable, Hashable {
    case free
    case grossing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "免费榜"
        case .grossing: return "畅销榜"
        }
    }
}

enum DiscoverRoute: Hashable {
    case news(NewsItem)
    case stock(StockQuote)
    case search(StockSearchResult)
    case game(GameRankItem, GameRankBoard)
}

enum DiscoverLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
    case cached
    case stale(String)
    case partial(String)

    var notice: String? {
        switch self {
        case .cached: return "显示上次缓存 · 获取时间见来源"
        case .stale(let message): return "更新失败，保留上次数据 · \(message)"
        case .partial(let message): return "部分来源未更新 · \(message)"
        default: return nil
        }
    }
}

struct NewsFeedResponse: Codable {
    let channel: String
    let updatedAt: String
    let sources: [String]?
    let unavailableSources: [String]?
    let items: [NewsItem]
}

struct NewsItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let link: String
    let publishedAt: String?
    let channel: String
    let rank: Int?
    var section: String? = nil
    var topics: [String]? = nil
    var fetchedAt: String? = nil

    var topicIDs: Set<String> { Set((topics ?? []) + [section].compactMap { $0 }) }
    func mergingTopics(from other: NewsItem) -> NewsItem {
        var result = self
        result.topics = Array(topicIDs.union(other.topicIDs)).sorted()
        return result
    }

    var url: URL? { URL(string: link) }
    var displayTitle: String { NewsText.plain(title) }
    var displaySummary: String { NewsText.plain(summary) }
}

struct NewsSectionOption: Identifiable, Hashable {
    let id: String
    let title: String
}

extension DiscoverChannel {
    var newsSections: [NewsSectionOption] {
        switch self {
        case .ai:
            return [
                NewsSectionOption(id: "all", title: "全部"),
                NewsSectionOption(id: "game-ai", title: "游戏应用"),
                NewsSectionOption(id: "coding", title: "程序开发"),
                NewsSectionOption(id: "gametech", title: "游戏科技"),
                NewsSectionOption(id: "vendor", title: "厂商动态")
            ]
        case .headline:
            return [
                NewsSectionOption(id: "all", title: "全部"),
                NewsSectionOption(id: "domestic", title: "国内"),
                NewsSectionOption(id: "world", title: "国际"),
                NewsSectionOption(id: "military", title: "军事"),
                NewsSectionOption(id: "tech", title: "科技"),
                NewsSectionOption(id: "auto", title: "汽车")
            ]
        case .game:
            return [
                NewsSectionOption(id: "all", title: "全部"),
                NewsSectionOption(id: "cn", title: "国内"),
                NewsSectionOption(id: "global", title: "国际")
            ]
        case .market, .music, .weibo:
            return []
        }
    }

    func matches(section: String, itemSection: String?, topics: [String]? = nil) -> Bool {
        section == "all" || itemSection == section || (topics ?? []).contains(section)
    }
}

struct SteamFeaturedResponse: Codable {
    let updatedAt: String
    let source: String
    let note: String
    let topSellers: [SteamItem]
    let specials: [SteamItem]
    let comingSoon: [SteamItem]
    let newReleases: [SteamItem]

    func items(for kind: SteamKind) -> [SteamItem] {
        switch kind {
        case .topSellers: return topSellers
        case .specials: return specials
        case .comingSoon: return comingSoon
        }
    }
}

struct SteamItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let discounted: Bool
    let discountPercent: Int
    let originalPrice: Int?
    let finalPrice: Int?
    let currency: String
    let headerImage: String

    var headerURL: URL? { URL(string: headerImage) }
    var storeURL: URL? { URL(string: "https://store.steampowered.com/app/\(id)/?l=schinese") }

    var discountText: String? {
        guard discounted, discountPercent > 0 else { return nil }
        return "-\(discountPercent)%"
    }

    var originalPriceText: String? {
        guard discounted, let originalPrice else { return nil }
        return Self.price(originalPrice, currency: currency)
    }

    var finalPriceText: String {
        guard let finalPrice else { return "价格未公布" }
        if finalPrice == 0 { return "免费游玩" }
        return Self.price(finalPrice, currency: currency)
    }

    static func price(_ cents: Int, currency: String) -> String {
        let symbol = currency == "CNY" ? "¥" : currency == "USD" ? "$" : ""
        let value = Double(cents) / 100
        if value == value.rounded() { return "\(symbol)\(Int(value))" }
        return "\(symbol)\(String(format: "%.2f", value))"
    }
}

struct WeiboHotResponse: Codable {
    let updatedAt: String
    let source: String
    let note: String
    let items: [WeiboHotItem]
}

struct WeiboHotItem: Codable, Identifiable, Hashable {
    let rank: Int
    let id: String
    let word: String
    let note: String
    let category: String
    let tag: String
    let hotValue: Int
    let link: String

    var url: URL? { URL(string: link) }

    var hotText: String {
        guard hotValue > 0 else { return "" }
        if hotValue >= 100_000_000 {
            return String(format: "%.1f亿", Double(hotValue) / 100_000_000)
        }
        if hotValue >= 10_000 {
            return String(format: "%.1f万", Double(hotValue) / 10_000)
        }
        return "\(hotValue)"
    }
}

struct AIPaperFeedResponse: Codable {
    let category: String
    let categoryName: String
    let updatedAt: String
    let source: String
    let papers: [AIPaper]
}

struct AIPaper: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let authors: String
    let publishedAt: String?
    let link: String
    let category: String

    var url: URL? { URL(string: link) }
    var displayTitle: String { NewsText.plain(title) }
    var displaySummary: String { NewsText.plain(summary) }
}

enum NewsText {
    static func plain(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        var text = value
        for _ in 0..<3 {
            text = text.replacingOccurrences(of: "<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "<script\\b[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<style\\b[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: " ", options: .regularExpression)
            text = decode(text)
        }
        text = text.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: " ", options: .regularExpression)
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ text: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "mdash": "—", "ndash": "–", "hellip": "…"
        ]
        var output = text
        for (name, value) in named {
            output = output.replacingOccurrences(of: "&\(name);", with: value, options: .caseInsensitive)
        }
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") else { return output }
        let ns = output as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let raw = ns.substring(with: match.range(at: 1))
            let code = raw.lowercased().hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw, radix: 10)
            if let code, let scalar = UnicodeScalar(code) {
                result.append(Character(scalar))
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}

struct GameRankResponse: Codable {
    let board: String
    let boardName: String
    let updatedAt: String
    let source: String
    let note: String?
    let items: [GameRankItem]
}

struct GameRankItem: Codable, Identifiable, Hashable {
    let rank: Int
    let id: String
    let name: String
    let artist: String
    let category: String
    let icon: String
    let releaseDate: String
    let link: String

    var url: URL? { URL(string: link) }
    var iconURL: URL? { URL(string: icon) }

    var releaseText: String {
        guard let date = DiscoverFormat.date(from: releaseDate) else { return releaseDate }
        return date.formatted(.dateTime.year().month().day())
    }
}

struct AppStoreLookupResponse: Decodable {
    let resultCount: Int
    let results: [AppStoreAppDetail]
}

struct AppStoreAppDetail: Decodable, Identifiable, Hashable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let sellerName: String?
    let artworkUrl512: String?
    let artworkUrl100: String?
    let primaryGenreName: String?
    let genres: [String]?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let formattedPrice: String?
    let price: Double?
    let releaseDate: String?
    let currentVersionReleaseDate: String?
    let version: String?
    let fileSizeBytes: String?
    let minimumOsVersion: String?
    let contentAdvisoryRating: String?
    let languageCodesISO2A: [String]?
    let trackViewUrl: String?
    let screenshotUrls: [String]?
    let ipadScreenshotUrls: [String]?
    let summaryText: String?

    enum CodingKeys: String, CodingKey {
        case trackId, trackName, artistName, sellerName, artworkUrl512, artworkUrl100
        case primaryGenreName, genres, averageUserRating, userRatingCount, formattedPrice, price
        case releaseDate, currentVersionReleaseDate, version, fileSizeBytes, minimumOsVersion
        case contentAdvisoryRating, languageCodesISO2A, trackViewUrl, screenshotUrls, ipadScreenshotUrls
        case summaryText = "description"
    }

    var id: Int { trackId }

    var iconURL: URL? {
        let raw = artworkUrl512 ?? artworkUrl100 ?? ""
        return URL(string: raw)
    }

    var appStoreURL: URL? {
        guard let trackViewUrl else { return nil }
        return URL(string: trackViewUrl)
    }

    var descriptionText: String {
        NewsText.plain(summaryText ?? "")
    }

    var categoryText: String {
        let raw = primaryGenreName ?? genres?.first ?? ""
        switch raw {
        case "", "Games": return "游戏"
        default: return raw
        }
    }

    var priceText: String {
        if let formattedPrice, !formattedPrice.isEmpty { return formattedPrice }
        guard let price else { return "—" }
        return price == 0 ? "免费" : String(format: "¥%.2f", price)
    }

    var sizeText: String {
        guard let fileSizeBytes, let bytes = Double(fileSizeBytes), bytes > 0 else { return "—" }
        if bytes >= 1_073_741_824 { return String(format: "%.2f GB", bytes / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", bytes / 1_048_576) }
        return String(format: "%.0f KB", bytes / 1024)
    }

    var ratingText: String {
        guard let averageUserRating else { return "暂无评分" }
        return String(format: "%.1f", averageUserRating)
    }

    var ratingCountText: String {
        guard let userRatingCount else { return "—" }
        if userRatingCount >= 10_000 { return String(format: "%.1f 万人评分", Double(userRatingCount) / 10_000) }
        return "\(userRatingCount) 人评分"
    }

    var releaseText: String {
        DiscoverFormat.longDate(releaseDate)
    }

    var updateText: String {
        DiscoverFormat.longDate(currentVersionReleaseDate)
    }

    var screenshots: [String] {
        let phone = screenshotUrls ?? []
        if !phone.isEmpty { return phone }
        return ipadScreenshotUrls ?? []
    }
}

struct MarketQuoteResponse: Decodable {
    let updatedAt: String
    let delayedMinutes: Int?
    let source: String
    let quotes: [StockQuote]
    let errors: [MarketQuoteError]?
}

struct MarketQuoteError: Decodable, Hashable {
    let symbol: String?
    let symbols: [String]?
    let message: String
}

struct StockQuote: Decodable, Identifiable, Hashable {
    let symbol: String
    let code: String
    let market: String
    let name: String
    let price: Double?
    let previousClose: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let change: Double?
    let changePercent: Double?
    let volumeLots: Double?
    let volume: Double?
    let amount: Double?
    let turnoverPercent: Double?
    let pe: Double?
    let marketCap: Double?
    let floatMarketCap: Double?
    let timestamp: String?
    let source: String?
    let delayedMinutes: Int?

    var id: String { symbol }

    var displayCode: String { "\(market) \(code)" }

    var isUp: Bool { (change ?? 0) > 0 }
    var isDown: Bool { (change ?? 0) < 0 }
}

struct MarketSearchResponse: Decodable {
    let query: String
    let results: [StockSearchResult]
    let source: String
}

struct StockSearchResult: Decodable, Identifiable, Hashable {
    let symbol: String
    let code: String
    let name: String
    let market: String
    let type: String

    var id: String { symbol }
    var displayCode: String { "\(market) \(code)" }
}

struct KlineResponse: Decodable {
    let symbol: String
    let code: String
    let name: String
    let days: Int
    let source: String
    let delayedMinutes: Int?
    let points: [KlinePoint]
}

struct KlinePoint: Decodable, Identifiable, Hashable {
    let date: String
    let open: Double?
    let close: Double?
    let high: Double?
    let low: Double?
    let volume: Double?
    let amount: Double?
    let volumeLots: Double?
    let amplitudePercent: Double?
    let changePercent: Double?
    let change: Double?
    let turnoverPercent: Double?

    var id: String { date }
    var chartValue: Double { close ?? open ?? high ?? low ?? 0 }
}

struct StockProfile: Decodable, Hashable {
    let symbol: String
    let name: String
    let industry: String?
    let region: String?
    let priceBook: Double?
    let volumeRatio: Double?
    let totalShares: Double?
    let floatShares: Double?
    let week52High: Double?
    let week52Low: Double?
    let roe: Double?
}

struct IntradayResponse: Decodable {
    let symbol: String
    let code: String
    let name: String
    let date: String
    let source: String
    let delayedMinutes: Int?
    let points: [IntradayPoint]
}

struct IntradayPoint: Decodable, Identifiable, Hashable {
    let time: String
    let price: Double?
    let volumeLots: Double?
    let amount: Double?

    var id: String { time }
}

struct StockFundFlowResponse: Decodable {
    let symbol: String
    let code: String
    let name: String
    let updatedAt: String
    let source: String
    let points: [FundFlowPoint]
}

struct FundFlowPoint: Decodable, Identifiable, Hashable {
    let date: String
    let mainNet: Double?
    let smallNet: Double?
    let mediumNet: Double?
    let largeNet: Double?
    let superLargeNet: Double?
    let mainNetPercent: Double?
    let smallNetPercent: Double?
    let mediumNetPercent: Double?
    let largeNetPercent: Double?
    let superLargeNetPercent: Double?

    var id: String { date }
    var isInflow: Bool { (mainNet ?? 0) >= 0 }
}

enum DiscoverFormat {
    static func date(from iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: iso) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    static func relative(_ iso: String?) -> String {
        guard let date = date(from: iso) else { return "时间未知" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 0 { return "刚刚" }
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 172_800 { return "昨天" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    static func clock(_ iso: String?) -> String {
        guard let date = date(from: iso) else { return "时间未知" }
        return date.formatted(.dateTime.hour().minute())
    }

    static func delay(_ minutes: Int?) -> String {
        guard let minutes else { return "来源未声明延迟" }
        return "来源声明延迟约 \(minutes) 分钟"
    }

    static func longDate(_ iso: String?) -> String {
        guard let date = date(from: iso) else { return iso ?? "—" }
        return date.formatted(.dateTime.year().month().day())
    }

    static func price(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    static func signedPrice(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value > 0 ? "+" : "")\(price(value))"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value > 0 ? "+" : "")\(String(format: "%.2f", value))%"
    }

    static func compactAmount(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if abs(value) >= 100_000_000 { return String(format: "%.2f 亿", value / 100_000_000) }
        if abs(value) >= 10_000 { return String(format: "%.1f 万", value / 10_000) }
        return String(format: "%.0f", value)
    }

    static func signedCompactAmount(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        if abs(value) >= 100_000_000 { return sign + String(format: "%.2f 亿", abs(value) / 100_000_000) }
        if abs(value) >= 10_000 { return sign + String(format: "%.1f 万", abs(value) / 10_000) }
        return sign + String(format: "%.0f", abs(value))
    }

    static func signedPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value > 0 ? "+" : "")\(String(format: "%.2f", value))%"
    }
}

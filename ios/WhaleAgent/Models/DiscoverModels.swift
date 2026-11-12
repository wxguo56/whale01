import Foundation

enum DiscoverChannel: String, CaseIterable, Identifiable, Hashable {
    case ai
    case headline
    case game
    case market

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI 科技"
        case .headline: return "时事"
        case .game: return "游戏"
        case .market: return "行情"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .headline: return "newspaper.fill"
        case .game: return "gamecontroller.fill"
        case .market: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum GameSection: String, CaseIterable, Identifiable, Hashable {
    case news
    case free
    case grossing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: return "资讯"
        case .free: return "免费榜"
        case .grossing: return "畅销榜"
        }
    }

    var board: GameRankBoard? {
        switch self {
        case .news: return nil
        case .free: return .free
        case .grossing: return .grossing
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
}

enum DiscoverLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct NewsFeedResponse: Decodable {
    let channel: String
    let updatedAt: String
    let sources: [String]?
    let unavailableSources: [String]?
    let items: [NewsItem]
}

struct NewsItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let link: String
    let publishedAt: String
    let channel: String
    let rank: Int?

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

struct GameRankResponse: Decodable {
    let board: String
    let boardName: String
    let updatedAt: String
    let source: String
    let note: String?
    let items: [GameRankItem]
}

struct GameRankItem: Decodable, Identifiable, Hashable {
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

struct MarketQuoteResponse: Decodable {
    let updatedAt: String
    let delayedMinutes: Int
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
    let delayedMinutes: Int
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

struct IntradayResponse: Decodable {
    let symbol: String
    let code: String
    let name: String
    let date: String
    let source: String
    let delayedMinutes: Int
    let points: [IntradayPoint]
}

struct IntradayPoint: Decodable, Identifiable, Hashable {
    let time: String
    let price: Double?
    let volumeLots: Double?
    let amount: Double?

    var id: String { time }
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
}

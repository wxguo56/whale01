import Foundation

enum DiscoverChannel: String, CaseIterable, Identifiable, Hashable {
    case ai
    case headline
    case market

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI 科技"
        case .headline: return "时事"
        case .market: return "行情"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .headline: return "newspaper.fill"
        case .market: return "chart.line.uptrend.xyaxis"
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

import Foundation

enum ToolEvidencePolicy {
    static let liveTools: Set<String> = ["get_weather", "get_current_location", "search_places", "open_navigation", "get_tech_news", "get_stock_quote", "get_stock_kline", "get_stock_intraday", "search_merchant_prices", "search_web", "fetch_web_content"]

    static func accepts(tool: String, data: [String: Any]?, now: Date = Date()) -> Bool {
        guard let data, data["simulated"] as? Bool != true else { return false }
        guard liveTools.contains(tool) else { return true }
        let source = data["source"] as? String ?? ""
        let sources = data["sources"] as? [String] ?? []
        guard !source.isEmpty || !sources.isEmpty else { return false }
        if tool == "get_stock_quote", (data["quotes"] as? [Any] ?? []).isEmpty { return false }
        if tool == "get_tech_news", (data["items"] as? [Any] ?? []).isEmpty { return false }
        if tool == "search_merchant_prices", (data["evidence"] as? [Any] ?? []).isEmpty { return false }
        let raw = ["fetchedAt", "updatedAt", "locatedAt", "openedAt"].compactMap { data[$0] as? String }.first
        guard let acquired = raw.flatMap(ToolDate.parse) else { return false }
        let age = now.timeIntervalSince(acquired)
        return age >= -60 && age <= (tool == "get_tech_news" ? 600 : 300)
    }
}

import CoreFoundation
import Foundation

/// 手机直连公开数据源的只读客户端。
/// 有自建后端时 DiscoverClient 会优先走后端；没有后端时走这里，
/// 保证安装后不依赖开发电脑或局域网。
final class DirectContentClient: @unchecked Sendable {
    static let shared = DirectContentClient()

    private let session: URLSession

    private struct Feed {
        let id: String
        let name: String
        let url: String
        let channels: Set<String>
        let requireAIKeyword: Bool
    }

    struct MarketSymbol {
        let symbol: String
        let code: String
        let market: String
    }

    private static let feeds: [Feed] = [
        Feed(id: "jiqizhixin", name: "机器之心", url: "https://www.jiqizhixin.com/rss", channels: ["ai"], requireAIKeyword: false),
        Feed(id: "qbitai", name: "量子位", url: "https://www.qbitai.com/feed", channels: ["ai"], requireAIKeyword: false),
        Feed(id: "ithome", name: "IT之家", url: "https://www.ithome.com/rss/", channels: ["ai", "headline"], requireAIKeyword: true),
        Feed(id: "36kr", name: "36氪", url: "https://36kr.com/feed", channels: ["ai", "headline"], requireAIKeyword: true),
        Feed(id: "bing-ai", name: "Bing 新闻", url: "https://www.bing.com/news/search?q=AI%20%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD&format=rss&setlang=zh-cn", channels: ["ai"], requireAIKeyword: false),
        Feed(id: "bing-headline", name: "Bing 新闻", url: "https://www.bing.com/news/search?q=%E4%BB%8A%E6%97%A5%E8%A6%81%E9%97%BB&format=rss&setlang=zh-cn", channels: ["headline"], requireAIKeyword: false),
        Feed(id: "sina-china", name: "新浪新闻", url: "https://rss.sina.com.cn/news/china/focus15.xml", channels: ["headline"], requireAIKeyword: false),
        Feed(id: "youxiputao", name: "游戏葡萄", url: "https://www.youxituoluo.com/feed", channels: ["game"], requireAIKeyword: false),
        Feed(id: "youxichaguan", name: "游戏茶馆", url: "https://www.youxichaguan.com/feed", channels: ["game"], requireAIKeyword: false),
        Feed(id: "chuapp", name: "触乐", url: "https://www.chuapp.com/feed", channels: ["game"], requireAIKeyword: false)
    ]

    private static let aiPattern = "(?:^|[^a-z])(ai|a\\.i\\.|agi|agent|llm|gpt|chatgpt|claude|gemini|deepseek|openai|anthropic|nvidia|transformer|diffusion|multimodal|大模型|人工智能|机器学习|深度学习|神经网络|智能体|生成式|多模态|算力|芯片)(?:$|[^a-z])"

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - News

    func news(channel: DiscoverChannel, limit: Int) async throws -> NewsFeedResponse {
        guard channel != .market else {
            throw DirectContentError.decode("行情频道没有新闻")
        }
        let feeds = Self.feeds.filter { $0.channels.contains(channel.rawValue) }
        let safeLimit = min(max(limit, 1), 40)

        var items: [NewsItem] = []
        var sources: [String] = []
        var unavailable: [String] = []

        await withTaskGroup(of: (String, [NewsItem]?, String?).self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let loaded = try await self.loadFeed(feed, channel: channel)
                        return (feed.name, loaded, nil)
                    } catch {
                        return (feed.name, nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                }
            }
            for await result in group {
                if let loaded = result.1 {
                    sources.append(result.0)
                    items.append(contentsOf: loaded)
                } else {
                    unavailable.append(result.0)
                }
            }
        }

        guard !items.isEmpty else {
            let detail = unavailable.isEmpty ? "资讯源没有返回可用条目" : "资讯源暂时不可用：\(Array(Set(unavailable)).joined(separator: "、"))"
            throw DirectContentError.notFound(detail)
        }

        var seenLinks = Set<String>()
        var seenTitles = Set<String>()
        let unique = items
            .filter { item in
                let titleKey = item.title.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
                if seenLinks.contains(item.link) || seenTitles.contains(titleKey) { return false }
                seenLinks.insert(item.link)
                seenTitles.insert(titleKey)
                return true
            }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(safeLimit)
            .enumerated()
            .map { index, item in
                NewsItem(
                    id: item.id,
                    title: item.title,
                    summary: item.summary,
                    source: item.source,
                    link: item.link,
                    publishedAt: item.publishedAt,
                    channel: item.channel,
                    rank: index + 1
                )
            }

        return NewsFeedResponse(
            channel: channel.rawValue,
            updatedAt: Self.isoNow(),
            sources: Array(Set(sources)).sorted(),
            unavailableSources: Array(Set(unavailable)).sorted(),
            items: Array(unique)
        )
    }

    private func loadFeed(_ feed: Feed, channel: DiscoverChannel) async throws -> [NewsItem] {
        guard let url = URL(string: feed.url) else { throw DirectContentError.decode("资讯源地址无效") }
        var request = URLRequest(url: url)
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "accept")
        request.setValue("WhaleAgent/0.5", forHTTPHeaderField: "user-agent")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw DirectContentError.decode("\(feed.name) 返回了无法识别的编码")
        }

        var blocks = Self.blocks(in: xml, tag: "item")
        if blocks.isEmpty { blocks = Self.blocks(in: xml, tag: "entry") }

        var items: [NewsItem] = []
        for block in blocks.prefix(30) {
            let title = Self.cleanText(Self.tag("title", in: block))
            let link = Self.cleanLink(Self.pickLink(block))
            guard !title.isEmpty, !link.isEmpty else { continue }
            let summary = String(Self.cleanText(Self.firstTag(["description", "summary", "content:encoded", "content"], in: block)).prefix(220))
            let haystack = title + "\n" + summary
            if feed.requireAIKeyword, channel == .ai,
               haystack.range(of: Self.aiPattern, options: [.regularExpression, .caseInsensitive]) == nil {
                continue
            }
            let published = Self.firstTag(["pubDate", "published", "updated", "dc:date"], in: block)
            items.append(NewsItem(
                id: Self.stableID(feed.id + "|" + link),
                title: title,
                summary: summary,
                source: feed.name,
                link: link,
                publishedAt: Self.isoDate(published),
                channel: channel.rawValue,
                rank: nil
            ))
        }
        return items
    }

    // MARK: - Game rank

    func gameRank(board: GameRankBoard, limit: Int) async throws -> GameRankResponse {
        let path = board == .free ? "topfreeapplications" : "topgrossingapplications"
        guard let url = URL(string: "https://itunes.apple.com/cn/rss/\(path)/limit=100/genre=6014/json") else {
            throw DirectContentError.decode("App Store 榜单地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("WhaleAgent/0.5", forHTTPHeaderField: "user-agent")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = payload["feed"] as? [String: Any] else {
            throw DirectContentError.decode("App Store 榜单返回了无法识别的数据")
        }

        let entries: [[String: Any]]
        if let list = feed["entry"] as? [[String: Any]] {
            entries = list
        } else if let single = feed["entry"] as? [String: Any] {
            entries = [single]
        } else {
            entries = []
        }

        let safeLimit = min(max(limit, 1), 100)
        var items: [GameRankItem] = []
        for (index, entry) in entries.enumerated() {
            guard items.count < safeLimit else { break }
            guard let name = ((entry["im:name"] as? [String: Any])?["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            let idValue = ((entry["id"] as? [String: Any])?["attributes"] as? [String: Any])?["im:id"] as? String ?? ""
            let artist = ((entry["im:artist"] as? [String: Any])?["label"] as? String) ?? ""
            let category = ((entry["category"] as? [String: Any])?["attributes"] as? [String: Any])?["label"] as? String ?? "游戏"
            let release = ((entry["im:releaseDate"] as? [String: Any])?["label"] as? String) ?? ""
            let images = entry["im:image"] as? [[String: Any]] ?? []
            let icon = (images.last?["label"] as? String ?? "").replacingOccurrences(of: "http://", with: "https://")
            let link = Self.rankLink(entry["link"])
            guard !link.isEmpty else { continue }
            items.append(GameRankItem(
                rank: index + 1,
                id: idValue,
                name: name,
                artist: artist,
                category: category,
                icon: icon,
                releaseDate: release,
                link: link
            ))
        }

        guard !items.isEmpty else { throw DirectContentError.notFound("App Store 榜单没有返回可用条目") }
        return GameRankResponse(
            board: board.rawValue,
            boardName: board.title,
            updatedAt: Self.isoNow(),
            source: "Apple App Store 中国区公开榜单",
            note: "榜单随 App Store 实时变化，仅展示公开排名，不构成推荐。",
            items: items
        )
    }

    private static func rankLink(_ raw: Any?) -> String {
        let object: [String: Any]?
        if let list = raw as? [[String: Any]] {
            object = list.first
        } else {
            object = raw as? [String: Any]
        }
        let href = (object?["attributes"] as? [String: Any])?["href"] as? String ?? ""
        return href.replacingOccurrences(of: "http://", with: "https://")
    }

    // MARK: - Market

    func indexes() async throws -> MarketQuoteResponse {
        try await quotes(symbols: ["sh000001", "sz399001", "sz399006", "sh000688"])
    }

    func quotes(symbols: [String]) async throws -> MarketQuoteResponse {
        let normalized = Self.dedupe(symbols.compactMap(Self.normalizeSymbol))
        guard !normalized.isEmpty else { throw DirectContentError.decode("没有识别出有效的 A 股代码") }
        guard normalized.count <= 20 else { throw DirectContentError.decode("一次最多查询 20 个股票") }

        let query = normalized.map(\.symbol).joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(query)") else {
            throw DirectContentError.decode("行情地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.setValue("https://gu.qq.com/", forHTTPHeaderField: "referer")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let text = Self.decodeGBK(data) ?? String(data: data, encoding: .utf8) else {
            throw DirectContentError.decode("行情源返回了无法识别的编码")
        }

        var quotes: [StockQuote] = []
        for match in Self.globalMatches("v_([a-z]{2}[0-9]{6})=\"([^\"]*)\"", in: text) {
            guard match.count >= 3, let quote = Self.parseQuote(symbol: match[1], body: match[2]) else { continue }
            quotes.append(quote)
        }
        guard !quotes.isEmpty else { throw DirectContentError.notFound("腾讯财经没有返回行情") }

        return MarketQuoteResponse(
            updatedAt: Self.isoNow(),
            delayedMinutes: 15,
            source: "腾讯财经公开行情",
            quotes: quotes,
            errors: nil
        )
    }

    func search(_ query: String) async throws -> MarketSearchResponse {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DirectContentError.decode("搜索词不能为空") }

        if let results = try? await searchSina(text), !results.isEmpty {
            return MarketSearchResponse(query: text, results: results, source: "新浪财经证券搜索")
        }
        let results = try await searchTencent(text)
        return MarketSearchResponse(query: text, results: results, source: "腾讯财经证券搜索")
    }

    func kline(symbol input: String, days: Int) async throws -> KlineResponse {
        guard let symbol = Self.normalizeSymbol(input) else { throw DirectContentError.decode("无法识别股票代码 \(input)") }
        let safeDays = min(max(days, 5), 500)
        let urlString = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(symbol.symbol),day,,,\(safeDays),qfq"
        guard let url = URL(string: urlString) else { throw DirectContentError.decode("日线地址无效") }
        let json = try await fetchJSON(url)
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let block = data[symbol.symbol] as? [String: Any] else {
            throw DirectContentError.notFound("腾讯财经未返回 \(symbol.symbol) 的日线")
        }
        let rawRows = (block["qfqday"] ?? block["day"] ?? block["hfqday"]) as? [Any] ?? []
        var points: [KlinePoint] = []
        for raw in rawRows {
            guard let row = raw as? [Any], row.count >= 6 else { continue }
            let date = String(describing: row[0])
            let close = Self.number(row[2])
            guard !date.isEmpty, close != nil else { continue }
            let lots = Self.number(row[5])
            points.append(KlinePoint(
                date: date,
                open: Self.number(row[1]),
                close: close,
                high: Self.number(row[3]),
                low: Self.number(row[4]),
                volume: lots.map { $0 * 100 },
                amount: nil,
                volumeLots: lots,
                amplitudePercent: nil,
                changePercent: nil,
                change: nil,
                turnoverPercent: nil
            ))
        }
        let qt = block["qt"] as? [String: Any]
        let quoteRow = qt?[symbol.symbol] as? [Any]
        let name = (quoteRow?.dropFirst().first as? String) ?? symbol.code
        let code = (quoteRow?.dropFirst(2).first as? String) ?? symbol.code
        return KlineResponse(
            symbol: symbol.symbol,
            code: code,
            name: name,
            days: safeDays,
            source: "腾讯财经公开行情",
            delayedMinutes: 15,
            points: points
        )
    }

    func intraday(symbol input: String) async throws -> IntradayResponse {
        guard let symbol = Self.normalizeSymbol(input) else { throw DirectContentError.decode("无法识别股票代码 \(input)") }
        let urlString = "https://web.ifzq.gtimg.cn/appstock/app/day/query?code=\(symbol.symbol)"
        guard let url = URL(string: urlString) else { throw DirectContentError.decode("分时地址无效") }
        let json = try await fetchJSON(url)
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let block = data[symbol.symbol] as? [String: Any] else {
            throw DirectContentError.notFound("腾讯财经未返回 \(symbol.symbol) 的分时")
        }
        let days = block["data"] as? [[String: Any]] ?? []
        guard let latest = days.max(by: { (($0["date"] as? String) ?? "") < (($1["date"] as? String) ?? "") }),
              let lines = latest["data"] as? [String], !lines.isEmpty else {
            throw DirectContentError.notFound("腾讯财经今天还没有 \(symbol.symbol) 的分时数据")
        }
        var points: [IntradayPoint] = []
        for line in lines {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let rawTime = String(parts[0])
            let time = rawTime.count == 4 ? "\(rawTime.prefix(2)):\(rawTime.suffix(2))" : rawTime
            guard let price = Self.numberFromText(String(parts[1])) else { continue }
            points.append(IntradayPoint(
                time: time,
                price: price,
                volumeLots: parts.count > 2 ? Self.numberFromText(String(parts[2])) : nil,
                amount: parts.count > 3 ? Self.numberFromText(String(parts[3])) : nil
            ))
        }
        let qt = block["qt"] as? [String: Any]
        let quoteRow = qt?[symbol.symbol] as? [Any]
        let name = (quoteRow?.dropFirst().first as? String) ?? symbol.code
        return IntradayResponse(
            symbol: symbol.symbol,
            code: symbol.code,
            name: name,
            date: (latest["date"] as? String) ?? "",
            source: "腾讯财经公开行情",
            delayedMinutes: 15,
            points: points
        )
    }

    private func searchSina(_ query: String) async throws -> [StockSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://suggest3.sinajs.cn/suggest/type=11,12,13,14,15&key=\(encoded)") else {
            throw DirectContentError.decode("搜索地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "referer")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let text = Self.decodeGBK(data) ?? String(data: data, encoding: .utf8),
              let captured = Self.capture("suggestvalue=\"([\\s\\S]*?)\"", in: text),
              captured.count > 1 else {
            return []
        }
        let match = captured[1]
        var results: [StockSearchResult] = []
        var seen = Set<String>()
        for row in match.split(separator: ";") {
            let fields = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }
            let code = fields[2].trimmingCharacters(in: .whitespaces)
            let rawSymbol = fields[3].trimmingCharacters(in: .whitespaces)
            let name = fields[4].trimmingCharacters(in: .whitespaces)
            guard let symbol = Self.normalizeSymbol(rawSymbol), symbol.code == code, !name.isEmpty, !seen.contains(symbol.symbol) else { continue }
            seen.insert(symbol.symbol)
            results.append(StockSearchResult(symbol: symbol.symbol, code: symbol.code, name: name, market: symbol.market, type: name.contains("指数") ? "index" : "stock"))
            if results.count >= 12 { break }
        }
        return results
    }

    private func searchTencent(_ query: String) async throws -> [StockSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://smartbox.gtimg.cn/s3/?q=\(encoded)&t=all") else {
            throw DirectContentError.decode("搜索地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.setValue("https://gu.qq.com/", forHTTPHeaderField: "referer")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let text = Self.decodeGBK(data) ?? String(data: data, encoding: .utf8),
              let captured = Self.capture("v_hint=\"([\\s\\S]*?)\"", in: text),
              captured.count > 1 else {
            return []
        }
        let match = captured[1]
        var results: [StockSearchResult] = []
        var seen = Set<String>()
        for row in match.split(separator: "^") {
            let fields = row.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            guard let symbol = Self.normalizeSymbol(fields[0] + fields[1]), !seen.contains(symbol.symbol) else { continue }
            let name = Self.decodeJSString(fields[2])
            guard !name.isEmpty else { continue }
            seen.insert(symbol.symbol)
            results.append(StockSearchResult(symbol: symbol.symbol, code: symbol.code, name: name, market: symbol.market, type: name.contains("指数") ? "index" : "stock"))
            if results.count >= 12 { break }
        }
        return results
    }

    private func fetchJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.setValue("https://gu.qq.com/", forHTTPHeaderField: "referer")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DirectContentError.decode("行情源返回了无法解析的数据")
        }
    }

    // MARK: - Parsing

    static func parseQuote(symbol raw: String, body: String) -> StockQuote? {
        let fields = body.components(separatedBy: "~")
        guard fields.count > 45, !fields[1].isEmpty, !fields[2].isEmpty else { return nil }
        guard let price = numberFromText(fields[3]) else { return nil }
        let lots = numberFromText(fields[6])
        let amountWan = numberFromText(fields[37])
        let marketCapYi = numberFromText(fields[45])
        let floatCapYi = numberFromText(fields[44])
        let market = String(raw.prefix(2)).uppercased()
        return StockQuote(
            symbol: raw,
            code: fields[2],
            market: market,
            name: fields[1],
            price: price,
            previousClose: numberFromText(fields[4]),
            open: numberFromText(fields[5]),
            high: numberFromText(fields[33]),
            low: numberFromText(fields[34]),
            change: numberFromText(fields[31]),
            changePercent: numberFromText(fields[32]),
            volumeLots: lots,
            volume: lots.map { $0 * 100 },
            amount: amountWan.map { $0 * 10_000 },
            turnoverPercent: numberFromText(fields[38]),
            pe: numberFromText(fields[39]),
            marketCap: marketCapYi.map { $0 * 100_000_000 },
            floatMarketCap: floatCapYi.map { $0 * 100_000_000 },
            timestamp: parseTencentTime(fields[30]),
            source: "腾讯财经公开行情",
            delayedMinutes: 15
        )
    }

    private static func parseTencentTime(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard digits.count == 14 else { return nil }
        let chars = Array(digits)
        return "\(String(chars[0...3]))-\(String(chars[4...5]))-\(String(chars[6...7]))T\(String(chars[8...9])):\(String(chars[10...11])):\(String(chars[12...13]))+08:00"
    }

    static func normalizeSymbol(_ input: String) -> MarketSymbol? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "")
        if let groups = capture("^(sh|sz|bj)([0-9]{6})$", in: value) { return makeSymbol(groups[1], groups[2]) }
        if let groups = capture("^([0-9]{6})\\.(sh|sz|bj)$", in: value) { return makeSymbol(groups[2], groups[1]) }
        if let groups = capture("^([01])\\.([0-9]{6})$", in: value) { return makeSymbol(groups[1] == "1" ? "sh" : "sz", groups[2]) }
        if let groups = capture("^([0-9]{6})$", in: value) {
            let code = groups[1]
            if code.first.map({ "569".contains($0) }) == true { return makeSymbol("sh", code) }
            if code.first.map({ "48".contains($0) }) == true { return makeSymbol("bj", code) }
            if code.first.map({ "013".contains($0) }) == true { return makeSymbol("sz", code) }
        }
        return nil
    }

    private static func makeSymbol(_ market: String, _ code: String) -> MarketSymbol {
        let prefix = market == "sh" ? "sh" : market == "bj" ? "bj" : "sz"
        return MarketSymbol(symbol: prefix + code, code: code, market: prefix.uppercased())
    }

    private static func dedupe(_ symbols: [MarketSymbol]) -> [MarketSymbol] {
        var seen = Set<String>()
        return symbols.filter { seen.insert($0.symbol).inserted }
    }

    // MARK: - Text helpers

    private static func blocks(in xml: String, tag: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>", options: [.caseInsensitive]) else { return [] }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    static func tag(_ name: String, in block: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return capture("<\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</\(escaped)>", in: block)?[1] ?? ""
    }

    private static func firstTag(_ names: [String], in block: String) -> String {
        for name in names {
            let value = tag(name, in: block)
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return ""
    }

    private static func pickLink(_ block: String) -> String {
        let direct = tag("link", in: block)
        if !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !direct.contains("<") { return direct }
        if let groups = capture("<link\\b[^>]*\\bhref\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>", in: block) { return groups[1] }
        if let groups = capture("<guid\\b[^>]*>([\\s\\S]*?)</guid>", in: block) { return groups[1] }
        return ""
    }

    private static func cleanLink(_ value: String) -> String {
        let text = cleanText(value)
        guard text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") else { return "" }
        return text
    }

    private static func cleanText(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        var text = value
        // RSS 摘要可能多层转义：CDATA 里套 &lt;p&gt;，甚至 &amp;lt;。
        // 每轮解实体并剥标签，多轮直到稳定，避免把 HTML 当正文显示。
        for _ in 0..<3 {
            text = text.replacingOccurrences(of: "<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "<script\\b[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<style\\b[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: " ", options: .regularExpression)
            text = decodeEntities(text)
        }
        text = text.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        while let amp = text[index...].firstIndex(of: "&") {
            output += text[index..<amp]
            if let semi = text[amp...].firstIndex(of: ";"), text.distance(from: amp, to: semi) <= 12 {
                let entity = String(text[text.index(after: amp)..<semi])
                if let decoded = decodeEntity(entity) {
                    output += decoded
                    index = text.index(after: semi)
                    continue
                }
            }
            output.append("&")
            index = text.index(after: amp)
        }
        output += text[index...]
        return output
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            guard let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(code) else { return nil }
            return String(scalar)
        }
        if entity.hasPrefix("#") {
            guard let code = UInt32(entity.dropFirst(), radix: 10), let scalar = UnicodeScalar(code) else { return nil }
            return String(scalar)
        }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "mdash": "—", "ndash": "–", "hellip": "…"
        ]
        return named[entity.lowercased()]
    }

    private static func isoDate(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return isoNow() }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return iso.string(from: date) }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return iso.string(from: date) }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd HH:mm:ss"] {
            rfc.dateFormat = format
            if let date = rfc.date(from: value) { return iso.string(from: date) }
        }
        return isoNow()
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func stableID(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func decodeGBK(_ data: Data) -> String? {
        let cfEncoding = CFStringEncoding(0x0632)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: data, encoding: encoding)
    }

    private static func decodeJSString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        if let data = ("\"" + escaped + "\"").data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let decoded = object as? String {
            return decoded
        }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return numberFromText(text) }
        return nil
    }

    private static func numberFromText(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "-" else { return nil }
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

    static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups = [""]
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else {
                groups.append("")
                continue
            }
            groups.append(String(text[range]))
        }
        return groups
    }

    private static func globalMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DirectContentError.decode("服务返回了无法识别的响应") }
        guard (200..<300).contains(http.statusCode) else { throw DirectContentError.http(http.statusCode) }
    }
}

enum DirectContentError: Error, LocalizedError {
    case http(Int)
    case notFound(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "公开数据源 HTTP \(code)，请稍后重试"
        case .notFound(let message):
            return message
        case .decode(let message):
            return message
        }
    }
}

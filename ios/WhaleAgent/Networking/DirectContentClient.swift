import CoreFoundation
import Foundation

/// 手机直连公开数据源的只读客户端。
/// 有自建后端时 DiscoverClient 会优先走后端；没有后端时走这里，
/// 保证安装后不依赖开发电脑或局域网。
final class DirectContentClient: @unchecked Sendable {
    static let shared = DirectContentClient()

    private let session: URLSession
    private var feedCache: [String: (data: Data, at: Date)] = [:]
    private let feedCacheLock = NSLock()

    private struct Feed {
        let id: String
        let name: String
        let url: String
        let channels: Set<String>
        let section: String
        let requireAIKeyword: Bool
        var matchPattern: String? = nil
        var allMatchPatterns: [String] = []
    }

    struct MarketSymbol {
        let symbol: String
        let code: String
        let market: String
    }

    private static let feeds: [Feed] = [
        // AI：全中文应用向资讯，只用带正文摘要的 RSS，禁止标题党；不拉论文与英文源。
        Feed(id: "mydrivers-ai", name: "快科技", url: "https://rss.mydrivers.com/rss.aspx?Tid=1", channels: ["ai"], section: "vendor", requireAIKeyword: true),
        Feed(id: "ithome-ai", name: "IT之家", url: "https://www.ithome.com/rss/", channels: ["ai"], section: "vendor", requireAIKeyword: true),
        Feed(id: "qbitai", name: "量子位", url: "https://www.qbitai.com/feed", channels: ["ai"], section: "vendor", requireAIKeyword: false),
        Feed(id: "ifanr-ai", name: "爱范儿", url: "https://www.ifanr.com/feed", channels: ["ai"], section: "vendor", requireAIKeyword: true),
        Feed(id: "putao-ai", name: "游戏葡萄", url: "https://www.youxituoluo.com/feed", channels: ["ai"], section: "game-ai", requireAIKeyword: true),
        Feed(id: "chaguan-ai", name: "游戏茶馆", url: "https://www.youxichaguan.com/feed", channels: ["ai"], section: "game-ai", requireAIKeyword: true),
        Feed(id: "chuapp-ai", name: "触乐", url: "https://www.chuapp.com/feed", channels: ["ai"], section: "game-ai", requireAIKeyword: true),
        Feed(id: "yystv-ai", name: "游研社", url: "https://www.yystv.cn/rss/feed", channels: ["ai"], section: "game-ai", requireAIKeyword: true),
        Feed(id: "ithome-game-ai", name: "IT之家 · 游戏", url: "https://www.ithome.com/rss/", channels: ["ai"], section: "game-ai", requireAIKeyword: true, matchPattern: "(游戏|玩家|电竞|手游|主机)"),
        Feed(id: "mydrivers-game-ai", name: "快科技 · 游戏", url: "https://rss.mydrivers.com/rss.aspx?Tid=1", channels: ["ai"], section: "game-ai", requireAIKeyword: true, matchPattern: "(游戏|玩家|电竞|手游|主机)"),
        Feed(id: "infoq-code", name: "InfoQ", url: "https://www.infoq.cn/feed", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "oschina-code", name: "开源中国", url: "https://www.oschina.net/news/rss", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "juejin-code", name: "掘金", url: "https://juejin.cn/rss", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "ithome-code", name: "IT之家 · 开发", url: "https://www.ithome.com/rss/", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "qbitai-code", name: "量子位 · 开发", url: "https://www.qbitai.com/feed", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "ifanr-code", name: "爱范儿 · 开发", url: "https://www.ifanr.com/feed", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "mydrivers-code", name: "快科技 · 开发", url: "https://rss.mydrivers.com/rss.aspx?Tid=1", channels: ["ai"], section: "coding", requireAIKeyword: true, matchPattern: "(编程|代码|程序员|开发者|开发工具|copilot|ide|api|智能体|agent|大模型|开源|框架|sdk)"),
        Feed(id: "putao-tech", name: "游戏葡萄 · 技术", url: "https://www.youxituoluo.com/feed", channels: ["ai"], section: "gametech", requireAIKeyword: false, matchPattern: "(gdc|开发者|引擎|渲染|技术|大会|ai|画质|光追|性能|云游戏)"),
        Feed(id: "chaguan-tech", name: "游戏茶馆 · 技术", url: "https://www.youxichaguan.com/feed", channels: ["ai"], section: "gametech", requireAIKeyword: false, matchPattern: "(gdc|开发者|引擎|渲染|技术|大会|ai|画质|光追|性能|云游戏)"),
        Feed(id: "chuapp-tech", name: "触乐 · 技术", url: "https://www.chuapp.com/feed", channels: ["ai"], section: "gametech", requireAIKeyword: false, matchPattern: "(gdc|开发者|引擎|渲染|技术|大会|ai|画质|光追|性能|云游戏)"),
        Feed(id: "yystv-tech", name: "游研社 · 技术", url: "https://www.yystv.cn/rss/feed", channels: ["ai"], section: "gametech", requireAIKeyword: false, matchPattern: "(gdc|开发者|引擎|渲染|技术|大会|ai|画质|光追|性能|云游戏)"),
        Feed(id: "ithome-gametech", name: "IT之家 · 游戏技术", url: "https://www.ithome.com/rss/", channels: ["ai"], section: "gametech", requireAIKeyword: false, allMatchPatterns: ["(游戏|玩家|电竞|主机|掌机|显卡|gpu|steam)", "(技术|引擎|渲染|gdc|ai|性能|画质|光追|云游戏|开发者)"]),
        Feed(id: "mydrivers-gametech", name: "快科技 · 游戏技术", url: "https://rss.mydrivers.com/rss.aspx?Tid=1", channels: ["ai"], section: "gametech", requireAIKeyword: false, allMatchPatterns: ["(游戏|玩家|电竞|主机|掌机|显卡|gpu|steam)", "(技术|引擎|渲染|gdc|ai|性能|画质|光追|云游戏|开发者)"]),
        Feed(id: "ithome", name: "IT之家", url: "https://www.ithome.com/rss/", channels: ["ai", "headline"], section: "tech", requireAIKeyword: true),

        // 时事：中新网国内/国际/要闻每天滚动更新；人民网保留权威深度稿。
        // 军事用 Google 新闻补时效，汽车用 IT之家与快科技的汽车关键词补时效。
        Feed(id: "chinanews-china", name: "中国新闻网 · 国内", url: "https://www.chinanews.com.cn/rss/china.xml", channels: ["headline"], section: "domestic", requireAIKeyword: false),
        Feed(id: "chinanews-world", name: "中国新闻网 · 国际", url: "https://www.chinanews.com.cn/rss/world.xml", channels: ["headline"], section: "world", requireAIKeyword: false),
        Feed(id: "chinanews-top", name: "中国新闻网 · 要闻", url: "https://www.chinanews.com.cn/rss/importnews.xml", channels: ["headline"], section: "top", requireAIKeyword: false),
        Feed(id: "people-politics", name: "人民网 · 国内", url: "https://www.people.com.cn/rss/politics.xml", channels: ["headline"], section: "domestic", requireAIKeyword: false),
        Feed(id: "people-world", name: "人民网 · 国际", url: "https://www.people.com.cn/rss/world.xml", channels: ["headline"], section: "world", requireAIKeyword: false),
        Feed(id: "people-military", name: "人民网 · 军事", url: "https://www.people.com.cn/rss/military.xml", channels: ["headline"], section: "military", requireAIKeyword: false),
        Feed(id: "people-auto", name: "人民网 · 汽车", url: "https://www.people.com.cn/rss/auto.xml", channels: ["headline"], section: "auto", requireAIKeyword: false),
        Feed(id: "people-it", name: "人民网 · 科技", url: "https://www.people.com.cn/rss/it.xml", channels: ["headline"], section: "tech", requireAIKeyword: false),
        Feed(id: "google-military", name: "Google 新闻 · 军事", url: "https://news.google.com/rss/search?q=%E5%86%9B%E4%BA%8B&hl=zh-CN&gl=CN&ceid=CN:zh-Hans", channels: ["headline"], section: "military", requireAIKeyword: false),
        Feed(id: "ithome-auto", name: "IT之家 · 汽车", url: "https://www.ithome.com/rss/", channels: ["headline"], section: "auto", requireAIKeyword: false, matchPattern: "(汽车|车型|比亚迪|特斯拉|新能源|电动车|自动驾驶|智驾|小米汽车|问界|理想|蔚来|小鹏|吉利|长安|奇瑞|奥迪|宝马|奔驰|丰田|大众|本田|日产|SUV|轿车|MPV|座舱|充电)"),
        Feed(id: "mydrivers-auto", name: "快科技 · 汽车", url: "https://rss.mydrivers.com/rss.aspx?Tid=1", channels: ["headline"], section: "auto", requireAIKeyword: false, matchPattern: "(汽车|车型|比亚迪|特斯拉|新能源|电动车|自动驾驶|智驾|小米汽车|问界|理想|蔚来|小鹏|吉利|长安|奇瑞|奥迪|宝马|奔驰|丰田|大众|本田|日产|SUV|轿车|MPV|座舱|充电)"),
        Feed(id: "gnews-top", name: "Google 头条", url: "https://news.google.com/rss?hl=zh-CN&gl=CN&ceid=CN:zh-Hans", channels: ["headline"], section: "top", requireAIKeyword: false),

        // 游戏：国内外媒体分开，Steam 榜单走商店公开接口
        Feed(id: "youxiputao", name: "游戏葡萄", url: "https://www.youxituoluo.com/feed", channels: ["game"], section: "cn", requireAIKeyword: false),
        Feed(id: "youxichaguan", name: "游戏茶馆", url: "https://www.youxichaguan.com/feed", channels: ["game"], section: "cn", requireAIKeyword: false),
        Feed(id: "chuapp", name: "触乐", url: "https://www.chuapp.com/feed", channels: ["game"], section: "cn", requireAIKeyword: false),
        Feed(id: "ign", name: "IGN", url: "https://feeds.ign.com/ign/all", channels: ["game"], section: "global", requireAIKeyword: false),
        Feed(id: "gamespot", name: "GameSpot", url: "https://www.gamespot.com/feeds/news", channels: ["game"], section: "global", requireAIKeyword: false)
    ]

    private static let aiPattern = "(?:^|[^a-z])(ai|a\\.i\\.|agi|agent|llm|gpt|chatgpt|claude|gemini|deepseek|openai|anthropic|nvidia|transformer|diffusion|multimodal|大模型|人工智能|机器学习|深度学习|神经网络|智能体|生成式|多模态|算力|芯片)(?:$|[^a-z])"
    private static let paperPattern = "(arxiv|论文|预印本)"
    private static let spamPattern = "(彩金|博彩|开户|电子游艺|pg游戏|赌博|私服|外挂|代充|注册送|凯发|新葡京|威尼斯人|bet365|太阳城|正规吗)"

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - News

    func news(channel: DiscoverChannel, section: String = "all", limit: Int) async throws -> NewsFeedResponse {
        guard channel == .ai || channel == .headline || channel == .game else {
            throw DirectContentError.decode("该频道没有新闻列表")
        }
        let feeds = Self.feeds.filter {
            $0.channels.contains(channel.rawValue) && (section == "all" || $0.section == section)
        }
        guard !feeds.isEmpty else {
            throw DirectContentError.notFound("这个分类暂时没有配置资讯源")
        }
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
        var rankedItems = items
            .filter { item in
                // 分标签去重：同一篇稿子可以同时属于“游戏科技”和“厂商动态”，
                // 但每个标签内部不能重复；“全部”仍按链接全局去重。
                let scope = section == "all" ? "" : (item.section ?? "") + "|"
                let titleKey = scope + item.title.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
                let linkKey = scope + item.link
                if seenLinks.contains(linkKey) || seenTitles.contains(titleKey) { return false }
                seenLinks.insert(linkKey)
                seenTitles.insert(titleKey)
                return true
            }
            .sorted { $0.publishedAt > $1.publishedAt }

        if channel == .ai, section == "all" {
            // 厂商新闻更新最快，若只按时间取前 40 条，其它标签页会被挤空。
            // 这里在最新 40 条之外，为每个主题再补 12 条，保证每个分类都有内容。
            var selected = Array(rankedItems.prefix(safeLimit))
            var selectedIDs = Set(selected.map(\.id))
            let sections = ["game-ai", "coding", "gametech", "vendor", "media", "tech"]
            for sectionID in sections {
                let extra = rankedItems
                    .filter { $0.section == sectionID && !selectedIDs.contains($0.id) }
                    .prefix(12)
                for item in extra { selectedIDs.insert(item.id) }
                selected.append(contentsOf: extra)
            }
            rankedItems = selected.sorted { $0.publishedAt > $1.publishedAt }
        } else if channel == .headline, section == "all" {
            // 时事源更新频率差异很大：只取最新 40 条会让军事、汽车等低频频道整栏空白。
            // 最新 40 条之外，每个分栏再补 10 条，保证“国内/国际/军事/科技/汽车”都有真实内容。
            var selected = Array(rankedItems.prefix(safeLimit))
            var selectedIDs = Set(selected.map(\.id))
            for sectionID in ["domestic", "world", "military", "tech", "auto"] {
                let extra = rankedItems
                    .filter { $0.section == sectionID && !selectedIDs.contains($0.id) }
                    .prefix(10)
                for item in extra { selectedIDs.insert(item.id) }
                selected.append(contentsOf: extra)
            }
            rankedItems = selected.sorted { $0.publishedAt > $1.publishedAt }
        } else {
            rankedItems = Array(rankedItems.prefix(safeLimit))
        }

        let unique = rankedItems
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
                    rank: index + 1,
                    section: item.section
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
        let data: Data
        if let cached = cachedFeedData(for: feed.url) {
            data = cached
        } else {
            let (fresh, response) = try await session.data(for: request)
            try Self.check(response)
            storeFeedData(fresh, for: feed.url)
            data = fresh
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw DirectContentError.decode("\(feed.name) 返回了无法识别的编码")
        }

        var blocks = Self.blocks(in: xml, tag: "item")
        if blocks.isEmpty { blocks = Self.blocks(in: xml, tag: "entry") }

        var items: [NewsItem] = []
        for block in blocks.prefix(60) {
            var title = Self.cleanText(Self.tag("title", in: block))
            let link = Self.cleanLink(Self.pickLink(block))
            guard !title.isEmpty, !link.isEmpty else { continue }
            // Google News 的 description 是相关文章链接列表，不是摘要；标题也会带 “ - 媒体名” 后缀。
            let outlet = Self.cleanText(Self.tag("source", in: block))
            if !outlet.isEmpty, title.hasSuffix(" - \(outlet)") {
                title = String(title.dropLast(outlet.count + 3)).trimmingCharacters(in: .whitespaces)
            }
            let isAggregator = feed.url.contains("news.google.com")
            // 有些源 description 只有几个字，但 content:encoded 是完整正文；
            // 取最长的一段，避免把“标题党短句”当摘要展示。
            let summaryCandidates = ["description", "summary", "content:encoded", "content"].map {
                Self.cleanText(Self.tag($0, in: block))
            }
            let longestSummary = summaryCandidates.max { $0.count < $1.count } ?? ""
            var summary = isAggregator ? "" : longestSummary
            if summary.count > 220 { summary = String(summary.prefix(220)) }
            let haystack = title + "\n" + summary
            if channel == .ai,
               outlet.lowercased().contains("arxiv") || outlet.lowercased().contains("alphaxiv") {
                continue
            }
            if channel == .ai,
               haystack.range(of: Self.paperPattern, options: [.regularExpression, .caseInsensitive]) != nil
                || link.lowercased().contains("arxiv.org")
                || link.lowercased().contains("alphaxiv.org") {
                continue
            }
            if channel == .ai,
               haystack.range(of: Self.spamPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }
            // AI 频道只保留中文标题且带真实正文摘要的条目：
            // 用户明确要求“不要只给标题的卡片”，宁缺毋滥。
            if channel == .ai {
                let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedSummary.count < 10 { continue }
                if !Self.containsCJK(title) { continue }
            }
            if let pattern = feed.matchPattern,
               haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil {
                continue
            }
            if !feed.allMatchPatterns.isEmpty {
                let matched = feed.allMatchPatterns.allSatisfy { pattern in
                    haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                }
                if !matched { continue }
            }
            if feed.requireAIKeyword, channel == .ai,
               haystack.range(of: Self.aiPattern, options: [.regularExpression, .caseInsensitive]) == nil {
                continue
            }
            let published = Self.firstTag(["pubDate", "published", "updated", "dc:date"], in: block)
            items.append(NewsItem(
                id: Self.stableID(feed.id + "|" + link),
                title: title,
                summary: summary,
                source: outlet.isEmpty ? feed.name : outlet,
                link: link,
                publishedAt: Self.isoDate(published),
                channel: channel.rawValue,
                rank: nil,
                section: feed.section
            ))
        }
        return items
    }

    private func cachedFeedData(for url: String) -> Data? {
        feedCacheLock.lock()
        defer { feedCacheLock.unlock() }
        guard let entry = feedCache[url], Date().timeIntervalSince(entry.at) < 300 else { return nil }
        return entry.data
    }

    private func storeFeedData(_ data: Data, for url: String) {
        feedCacheLock.lock()
        feedCache[url] = (data, Date())
        feedCacheLock.unlock()
    }

    // MARK: - Game rank

    // MARK: - AI papers

    func aiPapers(category: AIPaperCategory, limit: Int) async throws -> AIPaperFeedResponse {
        let safeLimit = min(max(limit, 1), 12)
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "cat:\(category.rawValue)"),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "max_results", value: String(safeLimit))
        ]
        guard let url = components?.url else { throw DirectContentError.decode("arXiv 地址无效") }

        var request = URLRequest(url: url)
        request.setValue("application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "accept")
        request.setValue("WhaleAgent/0.5 (iOS)", forHTTPHeaderField: "user-agent")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw DirectContentError.decode("arXiv 返回了无法识别的编码")
        }

        var papers: [AIPaper] = []
        for block in Self.blocks(in: xml, tag: "entry") {
            let title = Self.cleanText(Self.tag("title", in: block))
            guard !title.isEmpty else { continue }
            let rawLink = Self.cleanLink(Self.tag("id", in: block))
            let link = rawLink.isEmpty ? Self.cleanLink(Self.pickLink(block)) : rawLink
            let summary = String(Self.cleanText(Self.tag("summary", in: block)).prefix(420))
            let authors = Self.globalMatches("<author>[\\s\\S]*?<name>([\\s\\S]*?)</name>[\\s\\S]*?</author>", in: block)
                .compactMap { $0.count > 1 ? Self.cleanText($0[1]) : nil }
                .prefix(3)
                .joined(separator: "、")
            let primary = Self.capture("primary_category[^>]*term=\"([^\"]+)\"", in: block)?.last ?? category.rawValue
            papers.append(AIPaper(
                id: Self.stableID(link + "|" + title),
                title: title,
                summary: summary,
                authors: authors,
                publishedAt: Self.isoDate(Self.tag("published", in: block)),
                link: link,
                category: primary
            ))
        }
        guard !papers.isEmpty else {
            throw DirectContentError.notFound("arXiv 暂时没有返回 \(category.title) 论文")
        }
        return AIPaperFeedResponse(
            category: category.rawValue,
            categoryName: category.title,
            updatedAt: Self.isoNow(),
            source: "arXiv \(category.rawValue)",
            papers: papers
        )
    }

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

    func appStoreLookup(id: String) async throws -> AppStoreAppDetail {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) else {
            throw DirectContentError.decode("缺少有效的 App Store 应用编号")
        }
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(trimmed)&country=cn&entity=software") else {
            throw DirectContentError.decode("App Store 详情地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("WhaleAgent/0.6", forHTTPHeaderField: "user-agent")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)

        let payload: AppStoreLookupResponse
        do {
            payload = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        } catch {
            throw DirectContentError.decode("App Store 详情返回了无法识别的数据")
        }
        guard let app = payload.results.first else {
            throw DirectContentError.notFound("App Store 没有返回这个应用的详情")
        }
        return app
    }

    // MARK: - Steam

    func steamFeatured() async throws -> SteamFeaturedResponse {
        guard let url = URL(string: "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese") else {
            throw DirectContentError.decode("Steam 商店地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("WhaleAgent/0.7", forHTTPHeaderField: "user-agent")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectContentError.decode("Steam 商店返回了无法识别的数据")
        }

        func items(_ key: String) -> [SteamItem] {
            guard let block = payload[key] as? [String: Any],
                  let list = block["items"] as? [[String: Any]] else { return [] }
            var seen = Set<Int>()
            return list.compactMap { entry -> SteamItem? in
                guard let id = entry["id"] as? Int,
                      let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty, !seen.contains(id) else { return nil }
                seen.insert(id)
                let rawImage = (entry["header_image"] as? String)
                    ?? (entry["large_capsule_image"] as? String)
                    ?? (entry["small_capsule_image"] as? String)
                    ?? ""
                return SteamItem(
                    id: id,
                    name: name,
                    discounted: entry["discounted"] as? Bool ?? false,
                    discountPercent: entry["discount_percent"] as? Int ?? 0,
                    originalPrice: entry["original_price"] as? Int,
                    finalPrice: entry["final_price"] as? Int,
                    currency: entry["currency"] as? String ?? "CNY",
                    headerImage: rawImage.replacingOccurrences(of: "http://", with: "https://")
                )
            }
        }

        let top = items("top_sellers")
        let specials = items("specials")
        let coming = items("coming_soon")
        guard !top.isEmpty || !specials.isEmpty || !coming.isEmpty else {
            throw DirectContentError.notFound("Steam 商店没有返回榜单条目")
        }
        return SteamFeaturedResponse(
            updatedAt: Self.isoNow(),
            source: "Steam 商店中国区公开接口",
            note: "榜单与价格随 Steam 商店实时变化；人民币价格按商店返回的分单位换算。",
            topSellers: top,
            specials: specials,
            comingSoon: coming,
            newReleases: items("new_releases")
        )
    }

    // MARK: - Weibo hot search

    func weiboHot(limit: Int) async throws -> WeiboHotResponse {
        let safeLimit = min(max(limit, 1), 50)
        var firstError: Error?
        do {
            return try await loadWeiboHot(kind: "search", limit: safeLimit)
        } catch {
            firstError = error
        }
        do {
            return try await loadWeiboHot(kind: "band", limit: safeLimit)
        } catch {
            let previous = (firstError as? LocalizedError)?.errorDescription ?? firstError?.localizedDescription ?? "未知错误"
            throw DirectContentError.decode("微博热搜暂时不可用：\(previous)；备用榜：\(error.localizedDescription)")
        }
    }

    private func loadWeiboHot(kind: String, limit: Int) async throws -> WeiboHotResponse {
        let endpoint = kind == "band"
            ? "https://weibo.com/ajax/statuses/hot_band"
            : "https://weibo.com/ajax/side/hotSearch"
        guard let url = URL(string: endpoint) else {
            throw DirectContentError.decode("微博热搜地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "user-agent")
        request.setValue("https://weibo.com/", forHTTPHeaderField: "referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = payload["data"] as? [String: Any] else {
            throw DirectContentError.decode("微博热搜返回了无法识别的数据")
        }
        let entries: [[String: Any]]
        if kind == "band" {
            entries = dataObject["band_list"] as? [[String: Any]] ?? []
        } else {
            entries = dataObject["realtime"] as? [[String: Any]] ?? []
        }
        guard !entries.isEmpty else {
            throw DirectContentError.notFound("微博热搜没有返回条目")
        }

        var items: [WeiboHotItem] = []
        var seen = Set<String>()
        for entry in entries {
            guard items.count < limit else { break }
            if Self.weiboBool(entry["is_ad"]) { continue }
            let word = Self.text(entry["word"])
            guard !word.isEmpty, !seen.contains(word) else { continue }
            let realPosition = Self.weiboInt(entry["realpos"]) ?? 0
            if kind != "band", realPosition <= 0 { continue }
            let position = realPosition > 0 ? realPosition : items.count + 1
            let scheme = Self.text(entry["word_scheme"])
            seen.insert(word)
            items.append(WeiboHotItem(
                rank: position,
                id: "weibo-\(position)-\(word)",
                word: word,
                note: Self.text(entry["note"]),
                category: Self.text(entry["category"]),
                tag: Self.text(entry["label_name"]).isEmpty ? Self.text(entry["icon_desc"]) : Self.text(entry["label_name"]),
                hotValue: Self.weiboInt(entry["num"]) ?? 0,
                link: Self.weiboLink(word: word, scheme: scheme)
            ))
        }
        guard !items.isEmpty else {
            throw DirectContentError.notFound("微博热搜没有返回可用条目")
        }
        return WeiboHotResponse(
            updatedAt: Self.isoNow(),
            source: "微博公开热搜接口",
            note: "实时榜随微博变化，仅展示公开条目，不代表平台立场。",
            items: items
        )
    }

    // MARK: - Zhihu hot list

    func zhihuHot(limit: Int) async throws -> WeiboHotResponse {
        let safeLimit = min(max(limit, 1), 50)
        let endpoints = [
            "https://api.zhihu.com/topstory/hot-list?limit=\(safeLimit)",
            "https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?limit=\(safeLimit)&desktop=true"
        ]
        var firstError: Error?
        for endpoint in endpoints {
            do {
                return try await loadZhihuHot(endpoint: endpoint, limit: safeLimit)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        let previous = (firstError as? LocalizedError)?.errorDescription ?? firstError?.localizedDescription ?? "未知错误"
        throw DirectContentError.decode("知乎热榜暂时不可用：\(previous)")
    }

    private func loadZhihuHot(endpoint: String, limit: Int) async throws -> WeiboHotResponse {
        guard let url = URL(string: endpoint) else {
            throw DirectContentError.decode("知乎热榜地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "user-agent")
        request.setValue("https://www.zhihu.com/", forHTTPHeaderField: "referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = payload["data"] as? [[String: Any]] else {
            throw DirectContentError.decode("知乎热榜返回了无法识别的数据")
        }

        var items: [WeiboHotItem] = []
        for (index, entry) in entries.prefix(limit).enumerated() {
            guard let target = entry["target"] as? [String: Any] else { continue }
            let title = Self.text(target["title"])
            guard !title.isEmpty else { continue }
            let id = Self.text(target["id"])
            let type = Self.text(target["type"])
            let link = Self.zhihuLink(type: type, id: id, raw: Self.text(target["url"]))
            items.append(WeiboHotItem(
                rank: index + 1,
                id: "zhihu-\(id.isEmpty ? "\(index)" : id)",
                word: title,
                note: Self.text(target["excerpt"]),
                category: "知乎热榜",
                tag: index < 3 ? "热" : "",
                hotValue: Self.zhihuHeatValue(Self.text(entry["detail_text"])),
                link: link
            ))
        }
        guard !items.isEmpty else {
            throw DirectContentError.notFound("知乎热榜没有返回可用条目")
        }
        return WeiboHotResponse(
            updatedAt: Self.isoNow(),
            source: "知乎公开热榜接口",
            note: "榜单随知乎实时变化，仅展示公开条目，不代表平台立场。",
            items: items
        )
    }

    private static func weiboInt(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func text(_ raw: Any?) -> String {
        if let value = raw as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    private static func weiboBool(_ raw: Any?) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? Int { return value != 0 }
        return false
    }

    private static func weiboLink(word: String, scheme: String) -> String {
        let query = scheme.isEmpty ? word : scheme
        var components = URLComponents(string: "https://s.weibo.com/weibo")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url?.absoluteString ?? "https://s.weibo.com/"
    }

    static func zhihuHeatValue(_ detail: String) -> Int {
        guard let match = capture("([0-9]+(?:\\.[0-9]+)?)\\s*(亿|万)?", in: detail), match.count >= 2 else {
            return 0
        }
        let number = Double(match[1]) ?? 0
        let unit = match.count > 2 ? match[2] : ""
        if unit == "亿" { return Int(number * 100_000_000) }
        if unit == "万" { return Int(number * 10_000) }
        return Int(number)
    }

    static func zhihuLink(type: String, id: String, raw: String) -> String {
        if (raw.contains("/questions/") || type == "question"), !id.isEmpty {
            return "https://www.zhihu.com/question/\(id)"
        }
        if (raw.contains("/articles/") || type == "article"), !id.isEmpty {
            return "https://zhuanlan.zhihu.com/p/\(id)"
        }
        if !raw.isEmpty, let url = URL(string: raw), url.host?.contains("zhihu.com") == true {
            return raw
        }
        return "https://www.zhihu.com/hot"
    }

    // MARK: - Market

    func fundFlow(symbol input: String, days: Int) async throws -> StockFundFlowResponse {
        guard let symbol = Self.normalizeSymbol(input), symbol.market != "BJ" else {
            throw DirectContentError.decode("资金流暂不支持该证券 \(input)")
        }
        let safeDays = min(max(days, 1), 30)
        let secid = (symbol.market == "SH" ? "1." : "0.") + symbol.code
        let urlString = "https://push2.eastmoney.com/api/qt/stock/fflow/kline/get?klt=101&lmt=\(safeDays)&secid=\(secid)&fields1=f1,f2,f3,f7&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"
        guard let url = URL(string: urlString) else { throw DirectContentError.decode("资金流地址无效") }
        let json = try await fetchJSON(url, referer: "https://quote.eastmoney.com/")
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any] else {
            throw DirectContentError.notFound("东方财富未返回 \(symbol.symbol) 的资金流")
        }

        var points: [FundFlowPoint] = []
        for raw in (data["klines"] as? [Any] ?? []) {
            let fields = Self.text(raw).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else { continue }
            func value(_ index: Int) -> Double? { Self.numberFromText(fields[index]) }
            let hasPercent = fields.count >= 11
            points.append(FundFlowPoint(
                date: fields[0],
                mainNet: value(1),
                smallNet: value(2),
                mediumNet: value(3),
                largeNet: value(4),
                superLargeNet: value(5),
                mainNetPercent: hasPercent ? value(6) : nil,
                smallNetPercent: hasPercent ? value(7) : nil,
                mediumNetPercent: hasPercent ? value(8) : nil,
                largeNetPercent: hasPercent ? value(9) : nil,
                superLargeNetPercent: hasPercent ? value(10) : nil
            ))
        }
        guard !points.isEmpty else {
            throw DirectContentError.notFound("\(symbol.symbol) 暂时没有资金流数据")
        }
        return StockFundFlowResponse(
            symbol: symbol.symbol,
            code: Self.text(data["code"]).isEmpty ? symbol.code : Self.text(data["code"]),
            name: Self.text(data["name"]),
            updatedAt: Self.isoNow(),
            source: "东方财富公开资金流",
            points: points
        )
    }

    func todayFundFlows(symbols: [String]) async -> [String: FundFlowPoint] {
        let unique = Array(Set(symbols.map { $0.lowercased() })).sorted().prefix(10)
        var result: [String: FundFlowPoint] = [:]
        await withTaskGroup(of: (String, FundFlowPoint?).self) { group in
            for symbol in unique {
                group.addTask {
                    let point = try? await self.fundFlow(symbol: symbol, days: 1).points.last
                    return (symbol, point)
                }
            }
            for await (symbol, point) in group {
                if let point { result[symbol] = point }
            }
        }
        return result
    }

    func stockProfile(symbol input: String) async throws -> StockProfile {
        guard let symbol = Self.normalizeSymbol(input) else {
            throw DirectContentError.decode("无法识别股票代码 \(input)")
        }
        let secid = (symbol.market == "SH" ? "1." : "0.") + symbol.code
        let fields = "f57,f58,f50,f84,f85,f127,f128,f167,f173,f174,f175"
        guard let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=\(fields)") else {
            throw DirectContentError.decode("证券资料地址无效")
        }
        let json = try await fetchJSON(url, referer: "https://quote.eastmoney.com/")
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any] else {
            throw DirectContentError.notFound("东方财富未返回 \(symbol.code) 的证券资料")
        }
        func value(_ key: String) -> Double? { Self.number(data[key]) }
        func text(_ key: String) -> String? {
            let raw = Self.text(data[key])
            return raw.isEmpty ? nil : raw
        }
        return StockProfile(
            symbol: symbol.symbol,
            name: text("f58") ?? symbol.code,
            industry: text("f127"),
            region: text("f128"),
            priceBook: value("f167").map { $0 / 100 },
            volumeRatio: value("f50").map { $0 / 100 },
            totalShares: value("f84"),
            floatShares: value("f85"),
            week52High: value("f174").map { $0 / 100 },
            week52Low: value("f175").map { $0 / 100 },
            roe: value("f173")
        )
    }

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

    private func fetchJSON(_ url: URL, referer: String = "https://gu.qq.com/") async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.setValue(referer, forHTTPHeaderField: "referer")
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

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
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

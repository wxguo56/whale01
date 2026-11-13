import Foundation

actor FeedDataStore {
    struct Entry: Sendable { let data: Data; let fetchedAt: Date }
    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry, Error>] = [:]
    private var failures: [String: (count: Int, retryAt: Date)] = [:]

    func fetch(url: URL, force: Bool, session: URLSession) async throws -> Entry {
        let key = url.absoluteString
        if let pending = inFlight[key] { return try await pending.value }
        if !force, let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < 300 { return cached }
        if !force, let failure = failures[key], Date() < failure.retryAt {
            throw DirectContentError.decode("资讯源暂时不可用，正在退避重试")
        }
        let task = Task<Entry, Error> {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("application/rss+xml,application/atom+xml,application/xml,text/xml", forHTTPHeaderField: "Accept")
            request.setValue("WhaleAgent/0.6", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DirectContentError.decode("资讯源请求失败")
            }
            let cap = 4 * 1024 * 1024
            guard response.expectedContentLength <= cap else { throw DirectContentError.decode("资讯源内容过大") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < cap else { throw DirectContentError.decode("资讯源内容过大") }
                data.append(byte)
            }
            return Entry(data: data, fetchedAt: Date())
        }
        inFlight[key] = task
        do {
            let entry = try await task.value
            cache[key] = entry
            failures[key] = nil
            inFlight[key] = nil
            return entry
        } catch {
            inFlight[key] = nil
            let count = min(6, (failures[key]?.count ?? 0) + 1)
            failures[key] = (count, Date().addingTimeInterval(min(120, pow(2, Double(count)) * 5)))
            throw error
        }
    }
}

enum NewsSelection {
    static func select(_ items: [NewsItem], limit: Int, topics: [String] = []) -> [NewsItem] {
        var merged: [String: NewsItem] = [:]
        var titleLinks: [String: String] = [:]
        // Stable order makes metadata independent of network completion order.
        for var item in items.sorted(by: { ($0.link, $0.source, $0.section ?? "") < ($1.link, $1.source, $1.section ?? "") }) {
            let title = item.displayTitle.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
            let key = titleLinks[title] ?? item.link
            titleLinks[title] = key
            if let previous = merged[key] {
                item = previous.mergingTopics(from: item)
            }
            merged[key] = item
        }
        let ranked = merged.values.sorted {
            if ($0.publishedAt ?? "") != ($1.publishedAt ?? "") { return ($0.publishedAt ?? "") > ($1.publishedAt ?? "") }
            return $0.link < $1.link
        }
        let cap = max(1, min(limit, 40))
        var selected: [NewsItem] = []
        var ids = Set<String>()
        // Give each populated topic a slot within the caller's total budget.
        for topic in topics where selected.count < cap {
            if let item = ranked.first(where: { $0.topicIDs.contains(topic) && !ids.contains($0.id) }) {
                selected.append(item); ids.insert(item.id)
            }
        }
        for item in ranked where selected.count < cap && ids.insert(item.id).inserted { selected.append(item) }
        return selected.sorted {
            if ($0.publishedAt ?? "") != ($1.publishedAt ?? "") { return ($0.publishedAt ?? "") > ($1.publishedAt ?? "") }
            return $0.link < $1.link
        }
    }
}

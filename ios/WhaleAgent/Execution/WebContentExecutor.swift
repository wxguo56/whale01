import Foundation

/// Fetches public web pages and search result pages on-device. The result is
/// source material only: callers must not treat a snippet as the page body.
struct WebContentExecutor {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func search(query: String, limit: Int = 6) async throws -> JSONValue {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError(code: "empty_query", message: "搜索关键词不能为空")
        }
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "setlang", value: "zh-Hans"),
            URLQueryItem(name: "cc", value: "CN")
        ]
        guard let url = components.url else {
            throw ToolExecutionError(code: "invalid_query", message: "无法生成搜索地址")
        }
        let html = try await load(url: url)
        let results = Self.parseSearchResults(html, limit: max(1, min(limit, 10)))
        if results.isEmpty {
            throw ToolExecutionError(
                code: "empty_search",
                message: "没有解析到搜索结果；可能是网络被拦截或页面结构变化。请给出具体链接，或改用已知来源。"
            )
        }
        return .object([
            "query": .string(trimmed),
            "results": .array(results),
            "count": .number(Double(results.count)),
            "source": .string("bing_html"),
            "fetchedAt": .string(ToolDate.iso(Date())),
            "note": .string("搜索摘要只能用于找来源，不能当作网页正文或价格依据")
        ])
    }

    func fetch(urlString: String, maxChars: Int = 6000) async throws -> JSONValue {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw ToolExecutionError(code: "invalid_url", message: "只支持 http/https 链接")
        }
        let (data, response) = try await loadData(url: url)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ToolExecutionError(code: "http_error", message: "网页返回 HTTP \(status)，没有取得正文")
        }
        guard var html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ToolExecutionError(code: "decode_failed", message: "网页编码无法解析")
        }
        let title = Self.extractTitle(html)
        html = Self.stripHTML(html)
        let limit = max(1000, min(maxChars, 12000))
        let truncated = html.count > limit
        let text = truncated ? String(html.prefix(limit)) : html
        guard !text.isEmpty else {
            throw ToolExecutionError(code: "empty_content", message: "网页没有可提取的正文")
        }
        let finalURL = response.url?.absoluteString ?? trimmed
        return .object([
            "url": .string(trimmed),
            "finalURL": .string(finalURL),
            "title": .string(title.isEmpty ? "未命名网页" : title),
            "text": .string(text),
            "charCount": .number(Double(text.count)),
            "truncated": .bool(truncated),
            "source": .string("web"),
            "fetchedAt": .string(ToolDate.iso(Date()))
        ])
    }

    private func load(url: URL) async throws -> String {
        let (data, response) = try await loadData(url: url)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ToolExecutionError(code: "http_error", message: "网页返回 HTTP \(status)")
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ToolExecutionError(code: "decode_failed", message: "网页编码无法解析")
        }
        return html
    }

    private func loadData(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            return try await session.data(for: request)
        } catch {
            throw ToolExecutionError(code: "fetch_failed", message: "网页请求失败：\(error.localizedDescription)")
        }
    }

    private static func parseSearchResults(_ html: String, limit: Int) -> [JSONValue] {
        let blockPattern = #"(?is)<li class="b_algo".*?</li>"#
        let titlePattern = #"(?is)<h2[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"(?is)<p[^>]*>(.*?)</p>"#
        let blocks = matches(blockPattern, in: html)
        var results: [JSONValue] = []
        for block in blocks {
            guard let titleMatch = firstMatch(titlePattern, in: block), titleMatch.count >= 3 else { continue }
            let rawURL = decodeEntities(titleMatch[1])
            let title = stripHTML(titleMatch[2])
            guard !title.isEmpty else { continue }
            let url = rawURL.hasPrefix("/") ? "https://www.bing.com\(rawURL)" : rawURL
            guard url.hasPrefix("http") else { continue }
            let snippet = firstMatch(snippetPattern, in: block).map { stripHTML($0[1]) } ?? ""
            results.append(.object([
                "title": .string(title),
                "url": .string(url),
                "snippet": .string(snippet)
            ]))
            if results.count >= limit { break }
        }
        return results
    }

    private static func extractTitle(_ html: String) -> String {
        guard let match = firstMatch(#"(?is)<title[^>]*>(.*?)</title>"#, in: html) else { return "" }
        return stripHTML(match[1])
    }

    private static func stripHTML(_ raw: String) -> String {
        var text = raw
        text = replacing(#"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>"#, with: " ", in: text)
        text = replacing(#"(?is)<br\s*/?>"#, with: "\n", in: text)
        text = replacing(#"(?is)</(p|div|li|h[1-6]|tr|section|article)>"#, with: "\n", in: text)
        text = replacing(#"(?is)<[^>]+>"#, with: " ", in: text)
        text = decodeEntities(text)
        text = replacing(#"[ \t\x{00A0}]+"#, with: " ", in: text)
        text = replacing(#"\n[ \t]+"#, with: "\n", in: text)
        text = replacing(#"\n{3,}"#, with: "\n\n", in: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ pattern: String, with template: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            guard let swiftRange = Range(match.range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let swiftRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private static func decodeEntities(_ raw: String) -> String {
        var text = raw
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&middot;": "·", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        for match in matches.reversed() {
            guard
                let fullRange = Range(match.range, in: text),
                let valueRange = Range(match.range(at: 1), in: text)
            else { continue }
            let token = String(text[valueRange])
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            text.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return text
    }
}

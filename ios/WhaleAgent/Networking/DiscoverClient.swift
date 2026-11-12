import Foundation

enum DiscoverClientError: Error, LocalizedError {
    case missingBackend
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(String)
    case offline
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingBackend:
            return "还没有配置后端地址，请先在设置里填写"
        case .invalidURL:
            return "后端地址无效"
        case .invalidResponse:
            return "服务返回了无法识别的响应"
        case .unauthorized:
            return "访问令牌无效或已过期，请到设置里更新"
        case .server(let message):
            return message
        case .offline:
            return "网络不可用，请检查 Wi-Fi 或移动网络"
        case .decoding(let message):
            return "数据解析失败：\(message)"
        }
    }
}

final class DiscoverClient {
    private let session: URLSession

    private var hasBackend: Bool {
        !BackendConfig.currentBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 35
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func news(channel: DiscoverChannel, limit: Int = 20) async throws -> NewsFeedResponse {
        guard channel == .ai || channel == .headline || channel == .game else {
            throw DiscoverClientError.invalidURL
        }
        if !hasBackend {
            return try await DirectContentClient.shared.news(channel: channel, limit: limit)
        }
        do {
            return try await get("/v1/news", query: [
                URLQueryItem(name: "channel", value: channel.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ])
        } catch {
            return try await DirectContentClient.shared.news(channel: channel, limit: limit)
        }
    }

    func gameRank(board: GameRankBoard, limit: Int = 50) async throws -> GameRankResponse {
        if !hasBackend {
            return try await DirectContentClient.shared.gameRank(board: board, limit: limit)
        }
        do {
            return try await get("/v1/games/rank", query: [
                URLQueryItem(name: "board", value: board.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ])
        } catch {
            return try await DirectContentClient.shared.gameRank(board: board, limit: limit)
        }
    }

    func appStoreLookup(id: String) async throws -> AppStoreAppDetail {
        try await DirectContentClient.shared.appStoreLookup(id: id)
    }

    func weiboHot(limit: Int = 50) async throws -> WeiboHotResponse {
        try await DirectContentClient.shared.weiboHot(limit: limit)
    }

    func aiPapers(category: AIPaperCategory, limit: Int = 6) async throws -> AIPaperFeedResponse {
        try await DirectContentClient.shared.aiPapers(category: category, limit: limit)
    }

    func fundFlow(symbol: String, days: Int = 6) async throws -> StockFundFlowResponse {
        try await DirectContentClient.shared.fundFlow(symbol: symbol, days: days)
    }

    func todayFundFlows(symbols: [String]) async -> [String: FundFlowPoint] {
        await DirectContentClient.shared.todayFundFlows(symbols: symbols)
    }

    func quotes(symbols: [String]) async throws -> MarketQuoteResponse {
        guard !symbols.isEmpty else {
            return MarketQuoteResponse(updatedAt: "", delayedMinutes: 15, source: "", quotes: [], errors: [])
        }
        if !hasBackend {
            return try await DirectContentClient.shared.quotes(symbols: symbols)
        }
        do {
            return try await get("/v1/market/quote", query: [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
            ])
        } catch {
            return try await DirectContentClient.shared.quotes(symbols: symbols)
        }
    }

    func indexes() async throws -> MarketQuoteResponse {
        if !hasBackend {
            return try await DirectContentClient.shared.indexes()
        }
        do {
            return try await get("/v1/market/indexes", query: [])
        } catch {
            return try await DirectContentClient.shared.indexes()
        }
    }

    func search(_ query: String) async throws -> MarketSearchResponse {
        if !hasBackend {
            return try await DirectContentClient.shared.search(query)
        }
        do {
            return try await get("/v1/market/search", query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "12")
            ])
        } catch {
            return try await DirectContentClient.shared.search(query)
        }
    }

    func kline(symbol: String, days: Int = 160) async throws -> KlineResponse {
        if !hasBackend {
            return try await DirectContentClient.shared.kline(symbol: symbol, days: days)
        }
        do {
            return try await get("/v1/market/kline", query: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "days", value: String(days))
            ])
        } catch {
            return try await DirectContentClient.shared.kline(symbol: symbol, days: days)
        }
    }

    func intraday(symbol: String) async throws -> IntradayResponse {
        if !hasBackend {
            return try await DirectContentClient.shared.intraday(symbol: symbol)
        }
        do {
            return try await get("/v1/market/intraday", query: [
                URLQueryItem(name: "symbol", value: symbol)
            ])
        } catch {
            return try await DirectContentClient.shared.intraday(symbol: symbol)
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let url = try makeURL(path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let token = BackendConfig.authToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .cannotFindHost]
                .contains(error.code) {
                throw DiscoverClientError.offline
            }
            throw DiscoverClientError.server(error.localizedDescription)
        }

        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw DiscoverClientError.invalidResponse
        }
        if http.statusCode == 401 { throw DiscoverClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw DiscoverClientError.server(envelope.error.message)
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            throw DiscoverClientError.server("服务 HTTP \(http.statusCode)\(text.isEmpty ? "" : "：\(text.prefix(120))")")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DiscoverClientError.decoding(String(describing: error))
        }
    }

    private func makeURL(_ path: String, query: [URLQueryItem]) throws -> URL {
        let base = BackendConfig.currentBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw DiscoverClientError.missingBackend }
        guard var components = URLComponents(string: base) else { throw DiscoverClientError.invalidURL }
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw DiscoverClientError.invalidURL }
        return url
    }
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
    }
    let error: APIError
}

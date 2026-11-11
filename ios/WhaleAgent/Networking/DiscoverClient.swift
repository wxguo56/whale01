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

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 35
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func news(channel: DiscoverChannel, limit: Int = 20) async throws -> NewsFeedResponse {
        guard channel != .market else { throw DiscoverClientError.invalidURL }
        return try await get("/v1/news", query: [
            URLQueryItem(name: "channel", value: channel.rawValue),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    func quotes(symbols: [String]) async throws -> MarketQuoteResponse {
        guard !symbols.isEmpty else {
            return MarketQuoteResponse(updatedAt: "", delayedMinutes: 15, source: "", quotes: [], errors: [])
        }
        return try await get("/v1/market/quote", query: [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ])
    }

    func indexes() async throws -> MarketQuoteResponse {
        try await get("/v1/market/indexes", query: [])
    }

    func search(_ query: String) async throws -> MarketSearchResponse {
        try await get("/v1/market/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "12")
        ])
    }

    func kline(symbol: String, days: Int = 160) async throws -> KlineResponse {
        try await get("/v1/market/kline", query: [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "days", value: String(days))
        ])
    }

    func intraday(symbol: String) async throws -> IntradayResponse {
        try await get("/v1/market/intraday", query: [
            URLQueryItem(name: "symbol", value: symbol)
        ])
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

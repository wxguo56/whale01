import Foundation

enum AgentClientError: Error, LocalizedError {
    case invalidBackendURL
    case invalidResponse
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "后端地址无效"
        case .invalidResponse:
            return "后端返回了无法识别的响应"
        case .http(let status, let body):
            return "后端 HTTP \(status)：\(body)"
        case .decoding(let message):
            return "响应解析失败：\(message)"
        }
    }
}

actor AgentClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func health() async throws -> HealthResponse {
        try await send(path: "/healthz", method: "GET", body: Optional<EmptyBody>.none)
    }

    func startTurn(
        text: String,
        conversationId: String?,
        permissions: [String: String],
        deferExecution: Bool
    ) async throws -> AgentTurnResponse {
        let now = ISO8601DateFormatter().string(from: Date())
        let request = StartTurnRequest(
            text: text,
            now: now,
            timezone: TimeZone.current.identifier,
            autoConfirm: false,
            deferExecution: deferExecution,
            conversationId: conversationId,
            permissions: permissions
        )
        return try await send(path: "/v1/turns", method: "POST", body: request)
    }

    func submitToolResults(turnId: String, results: [ToolResultPayload]) async throws -> AgentTurnResponse {
        try await send(
            path: "/v1/turns/\(turnId)/tool-results",
            method: "POST",
            body: ToolResultSubmission(results: results)
        )
    }

    func confirmTurn(turnId: String, operationId: String, confirmed: Bool) async throws -> AgentTurnResponse {
        try await send(
            path: "/v1/turns/\(turnId)/confirm",
            method: "POST",
            body: ConfirmRequest(operationId: operationId, confirmed: confirmed)
        )
    }

    private func send<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?
    ) async throws -> T {
        let requestURL = try makeURL(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AgentClientError.http(http.statusCode, text)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AgentClientError.decoding(String(describing: error))
        }
    }

    private func makeURL(_ path: String) throws -> URL {
        guard var components = URLComponents(string: BackendConfig.currentBaseURLString) else {
            throw AgentClientError.invalidBackendURL
        }
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        guard let url = components.url else {
            throw AgentClientError.invalidBackendURL
        }
        return url
    }
}

private struct EmptyBody: Encodable {}

private struct StartTurnRequest: Encodable {
    let text: String
    let now: String
    let timezone: String
    let autoConfirm: Bool
    let deferExecution: Bool
    let conversationId: String?
    let permissions: [String: String]
}

private struct ConfirmRequest: Encodable {
    let operationId: String
    let confirmed: Bool
}

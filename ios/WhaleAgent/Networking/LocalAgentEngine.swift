import Foundation

protocol AgentTransport: Sendable {
    func health() async throws -> HealthResponse
    func turnSnapshot(turnId: String) async throws -> AgentTurnResponse
    func startTurn(
        text: String,
        conversationId: String?,
        permissions: [String: String],
        deferExecution: Bool
    ) async throws -> AgentTurnResponse
    func submitToolResults(turnId: String, results: [ToolResultPayload]) async throws -> AgentTurnResponse
}

enum LocalAgentConfig {
    static let model = "deepseek-chat"
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    static var apiKey: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "DeepSeekAPIKey") as? String) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return "" }
        return trimmed
    }

    static var isConfigured: Bool { !apiKey.isEmpty }
}

enum LocalAgentError: LocalizedError {
    case missingKey
    case unknownTurn
    case invalidResponse
    case http(Int, String)
    case model(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "本机直连缺少 DeepSeek 密钥。请在开发设置中切换到云后端，或重新安装包含密钥的构建。"
        case .unknownTurn:
            return "这一轮任务已经不存在，请重新发起。"
        case .invalidResponse:
            return "模型返回了无法识别的响应。"
        case .http(let status, let body):
            return "DeepSeek HTTP \(status)：\(body.prefix(300))"
        case .model(let message):
            return message
        }
    }
}

private struct ToolContract: Decodable {
    struct Tool: Decodable {
        let name: String
        let description: String
        let requiresConfirmation: Bool
        let inputSchema: JSONValue
    }

    let tools: [Tool]
}

struct DSMessage: Codable, Sendable {
    var role: String
    var content: String?
    var tool_calls: [DSToolCall]?
    var tool_call_id: String?
    var name: String?
}

struct DSToolCall: Codable, Sendable {
    let id: String
    let type: String
    let function: DSFunctionCall
}

struct DSFunctionCall: Codable, Sendable {
    let name: String
    let arguments: String
}

private struct DSRequest: Encodable {
    let model: String
    let messages: [DSMessage]
    let tools: [DSTool]
    let tool_choice: String
    let stream: Bool
}

private struct DSTool: Encodable {
    let type = "function"
    let function: DSToolFunction

    init(function: DSToolFunction) {
        self.function = function
    }
}

private struct DSToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: JSONValue
}

private struct DSResponse: Decodable {
    struct Choice: Decodable {
        let message: DSMessage
    }

    let choices: [Choice]
}

private struct LocalTurn: Codable {
    var turnId: String
    var conversationId: String
    var pending: [PendingTool]
    var batches: Int
    var permissions: [String: String]
}

actor LocalAgentEngine: AgentTransport {
    private let session: URLSession
    private let tools: [ToolContract.Tool]
    private let toolMap: [String: ToolContract.Tool]
    private var turns: [String: LocalTurn]

    private static let turnsKey = "whale.local.turns"

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        let loaded = Self.loadTools()
        tools = loaded
        toolMap = Dictionary(uniqueKeysWithValues: loaded.map { ($0.name, $0) })
        turns = Self.loadTurns()
    }

    func health() async throws -> HealthResponse {
        HealthResponse(
            status: LocalAgentConfig.isConfigured ? "ok" : "missing_key",
            modelMode: "deepseek-direct",
            executionMode: "ios",
            adapterConfigured: LocalAgentConfig.isConfigured,
            tools: tools.count,
            requiresDeferExecution: true,
            authRequired: false
        )
    }

    func startTurn(
        text: String,
        conversationId: String?,
        permissions: [String: String],
        deferExecution: Bool
    ) async throws -> AgentTurnResponse {
        guard LocalAgentConfig.isConfigured else { throw LocalAgentError.missingKey }
        let conversation = conversationId ?? Self.newId("conv")
        let turnId = Self.newId("turn")
        var history = loadHistory(conversation)
        history.append(DSMessage(role: "user", content: text, tool_calls: nil, tool_call_id: nil, name: nil))
        saveHistory(history, for: conversation)

        var turn = LocalTurn(
            turnId: turnId,
            conversationId: conversation,
            pending: [],
            batches: 0,
            permissions: permissions
        )
        if let clarification = RealDataGuard.preflightReply(for: text) {
            history.append(
                DSMessage(role: "assistant", content: clarification, tool_calls: nil, tool_call_id: nil, name: nil)
            )
            saveHistory(history, for: conversation)
            turns.removeValue(forKey: turn.turnId)
            saveTurns()
            return makeResponse(status: "completed", turn: turn, reply: clarification, pending: [])
        }

        let realDataIntent = RealDataGuard.intent(for: text)
        var message = try await callModel(history: history, permissions: permissions)
        if let realDataIntent,
           (message.tool_calls ?? []).isEmpty,
           !RealDataGuard.isClarifying(message.content ?? "") {
            history.append(
                DSMessage(
                    role: "assistant",
                    content: message.content,
                    tool_calls: nil,
                    tool_call_id: nil,
                    name: nil
                )
            )
            if let instruction = RealDataGuard.toolInstruction(for: realDataIntent) {
                history.append(
                    DSMessage(role: "system", content: instruction, tool_calls: nil, tool_call_id: nil, name: nil)
                )
            }
            message = try await callModel(history: history, permissions: permissions)
        }
        return try await advance(message: message, history: &history, turn: &turn)
    }

    func submitToolResults(turnId: String, results: [ToolResultPayload]) async throws -> AgentTurnResponse {
        guard var turn = turns[turnId] else { throw LocalAgentError.unknownTurn }
        var history = loadHistory(turn.conversationId)

        if !hasAssistantToolCalls(history, matching: turn.pending) {
            let calls = turn.pending.map { item in
                DSToolCall(
                    id: item.toolCallId,
                    type: "function",
                    function: DSFunctionCall(name: item.tool, arguments: encodeArguments(item.arguments))
                )
            }
            history.append(DSMessage(role: "assistant", content: nil, tool_calls: calls, tool_call_id: nil, name: nil))
        }

        let existingToolIds = Set(
            history.compactMap { $0.role == "tool" ? $0.tool_call_id : nil }
        )
        let novelResults = results.filter { !existingToolIds.contains($0.toolCallId) }
        for result in novelResults {
            history.append(
                DSMessage(
                    role: "tool",
                    content: encodeResult(result),
                    tool_calls: nil,
                    tool_call_id: result.toolCallId,
                    name: nil
                )
            )
        }
        saveHistory(history, for: turn.conversationId)

        if !novelResults.isEmpty {
            turn.batches += 1
        }
        if turn.batches > 3 {
            turns.removeValue(forKey: turn.turnId)
            saveTurns()
            return makeResponse(
                status: "completed_with_limits",
                turn: turn,
                reply: "这一轮已经执行了 3 批工具。为了不再重复写入，我先停在这里；你可以查看记录后继续。",
                pending: []
            )
        }

        let context = latestTurnContext(history)
        if let intent = RealDataGuard.intent(for: context.userText),
           let required = intent.requiredTool,
           !context.tools.contains(required),
           let instruction = RealDataGuard.toolInstruction(for: intent) {
            history.append(
                DSMessage(role: "system", content: instruction, tool_calls: nil, tool_call_id: nil, name: nil)
            )
            saveHistory(history, for: turn.conversationId)
        }

        turns[turn.turnId] = turn
        saveTurns()
        let message = try await callModel(history: history, permissions: turn.permissions)
        return try await advance(message: message, history: &history, turn: &turn)
    }

    func turnSnapshot(turnId: String) async throws -> AgentTurnResponse {
        guard let turn = turns[turnId] else {
            return AgentTurnResponse(
                contractVersion: "1.0",
                turnId: turnId,
                conversationId: "",
                status: "interrupted",
                reply: nil,
                modelMode: "deepseek-direct",
                executionMode: "ios",
                events: [],
                pending: [],
                task: nil
            )
        }
        let status = turn.pending.contains(where: \.requiresConfirmation)
            ? "awaiting_confirmation"
            : "awaiting_tool_results"
        return makeResponse(status: status, turn: turn, reply: nil, pending: turn.pending)
    }

    private func advance(
        message: DSMessage,
        history: inout [DSMessage],
        turn: inout LocalTurn
    ) async throws -> AgentTurnResponse {
        if let calls = message.tool_calls, !calls.isEmpty {
            history.append(
                DSMessage(role: "assistant", content: message.content, tool_calls: calls, tool_call_id: nil, name: nil)
            )
            let pending = calls.map { call -> PendingTool in
                let spec = toolMap[call.function.name]
                return PendingTool(
                    tool: call.function.name,
                    toolCallId: call.id.isEmpty ? Self.newId("call") : call.id,
                    operationId: Self.newId("op"),
                    arguments: decodeArguments(call.function.arguments),
                    requiresConfirmation: spec?.requiresConfirmation ?? true
                )
            }
            turn.pending = pending
            turns[turn.turnId] = turn
            saveHistory(history, for: turn.conversationId)
            saveTurns()
            let status = pending.contains(where: \.requiresConfirmation)
                ? "awaiting_confirmation"
                : "awaiting_tool_results"
            return makeResponse(status: status, turn: turn, reply: message.content, pending: pending)
        }

        let proposedReply = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let context = latestTurnContext(history)
        let reply = RealDataGuard.intent(for: context.userText).map {
            RealDataGuard.finalReply(for: $0, usedTools: context.tools, proposed: proposedReply)
        } ?? proposedReply
        history.append(
            DSMessage(
                role: "assistant",
                content: reply.isEmpty ? "我这次没有生成可执行的动作。" : reply,
                tool_calls: nil,
                tool_call_id: nil,
                name: nil
            )
        )
        saveHistory(history, for: turn.conversationId)
        turns.removeValue(forKey: turn.turnId)
        saveTurns()
        return makeResponse(
            status: "completed",
            turn: turn,
            reply: reply.isEmpty ? "我这次没有生成可执行的动作。" : reply,
            pending: []
        )
    }

    private func latestTurnContext(_ history: [DSMessage]) -> (userText: String, tools: Set<String>) {
        var userText = ""
        var callNames: [String: String] = [:]
        var successfulIds = Set<String>()
        for message in history.reversed() {
            if message.role == "user" {
                userText = message.content ?? ""
                break
            }
            if message.role == "assistant", let calls = message.tool_calls {
                for call in calls {
                    callNames[call.id] = call.function.name
                }
            }
            if message.role == "tool",
               let callId = message.tool_call_id,
               let content = message.content,
               let data = content.data(using: .utf8),
               let raw = try? JSONSerialization.jsonObject(with: data),
               let object = raw as? [String: Any],
               object["status"] as? String == "success" {
                let payload = object["data"] as? [String: Any]
                if (payload?["simulated"] as? Bool) != true {
                    successfulIds.insert(callId)
                }
            }
        }
        return (userText, Set(successfulIds.compactMap { callNames[$0] }))
    }

    private func callModel(history: [DSMessage], permissions: [String: String]) async throws -> DSMessage {
        var messages = [
            DSMessage(role: "system", content: systemPrompt(permissions: permissions), tool_calls: nil, tool_call_id: nil, name: nil)
        ]
        messages.append(contentsOf: Self.trimmedHistory(history, limit: 30))

        let requestBody = DSRequest(
            model: LocalAgentConfig.model,
            messages: messages,
            tools: tools.map { tool in
                DSTool(
                    function: DSToolFunction(
                        name: tool.name,
                        description: tool.description,
                        parameters: tool.inputSchema
                    )
                )
            },
            tool_choice: "auto",
            stream: false
        )

        var request = URLRequest(url: LocalAgentConfig.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(LocalAgentConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await sendModelRequest(request)
        guard let http = response as? HTTPURLResponse else { throw LocalAgentError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LocalAgentError.http(http.statusCode, body)
        }
        do {
            let decoded = try JSONDecoder().decode(DSResponse.self, from: data)
            guard let message = decoded.choices.first?.message else { throw LocalAgentError.invalidResponse }
            return message
        } catch let error as LocalAgentError {
            throw error
        } catch {
            throw LocalAgentError.model("模型响应解析失败：\(error.localizedDescription)")
        }
    }

    private func sendModelRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where [
            URLError.timedOut,
            URLError.networkConnectionLost,
            URLError.cannotConnectToHost
        ].contains(error.code) {
            try await Task.sleep(nanoseconds: 700_000_000)
            return try await session.data(for: request)
        }
    }

    private func systemPrompt(permissions: [String: String]) -> String {
        let baseline = loadText("assistant-system.v1") ?? "你是鲸鱼，一个中文日常事务助手。"
        let rules = loadText("direct-agent-rules") ?? ""
        let now = ISO8601DateFormatter().string(from: Date())
        let timezone = TimeZone.current.identifier
        let capabilities = tools
            .map { "- \($0.name)：\($0.description)" }
            .joined(separator: "\n")
        let permissionText = permissions
            .sorted { $0.key < $1.key }
            .map { "- \($0.key)：\($0.value)" }
            .joined(separator: "\n")
        let memoryText = MemoryStore.shared.snapshotText()

        return """
        \(baseline)

        ## 当前运行事实
        - 设备时间：\(now)
        - 设备时区：\(timezone)
        - 执行模式：真实 iOS 设备执行。只有本轮 tool.result 的 status=success 才能说完成。
        - 不要假设默认城市；时区不能当作当前位置。
        - 缺失关键信息时先追问，不猜参数。

        ## 本机执行规则
        \(rules)

        ## 可用工具
        \(capabilities.isEmpty ? "工具目录尚未加载，遇到执行请求先说明本机工具不可用。" : capabilities)

        ## 当前授权状态
        \(permissionText.isEmpty ? "尚未读取" : permissionText)

        ## 用户明确保存的偏好
        \(memoryText)
        - 偏好只用于建议和默认选择，不代表用户授权执行任何写操作。
        """
    }

    private func makeResponse(
        status: String,
        turn: LocalTurn,
        reply: String?,
        pending: [PendingTool]
    ) -> AgentTurnResponse {
        AgentTurnResponse(
            contractVersion: "1.0",
            turnId: turn.turnId,
            conversationId: turn.conversationId,
            status: status,
            reply: reply,
            modelMode: "deepseek-direct",
            executionMode: "ios",
            events: [],
            pending: pending,
            task: nil
        )
    }

    private func hasAssistantToolCalls(_ history: [DSMessage], matching pending: [PendingTool]) -> Bool {
        for message in history.reversed() {
            if message.role == "tool" { continue }
            guard message.role == "assistant", let calls = message.tool_calls else { return false }
            let ids = Set(calls.map(\.id))
            return pending.allSatisfy { ids.contains($0.toolCallId) }
        }
        return false
    }

    static func trimmedHistory(_ history: [DSMessage], limit: Int = 30) -> [DSMessage] {
        let slice = history.count > limit ? Array(history.suffix(limit)) : history
        var sanitized: [DSMessage] = []
        var index = 0
        while index < slice.count {
            let message = slice[index]
            if message.role == "tool" {
                index += 1
                continue
            }
            if message.role == "assistant", let calls = message.tool_calls, !calls.isEmpty {
                let expected = Set(calls.map(\.id))
                var cursor = index + 1
                var delivered = Set<String>()
                while cursor < slice.count, slice[cursor].role == "tool" {
                    if let id = slice[cursor].tool_call_id { delivered.insert(id) }
                    cursor += 1
                }
                if expected.isSubset(of: delivered) {
                    sanitized.append(contentsOf: slice[index..<cursor])
                }
                index = cursor
                continue
            }
            sanitized.append(message)
            index += 1
        }
        return sanitized
    }

    private func encodeArguments(_ arguments: [String: JSONValue]) -> String {
        let data = (try? JSONEncoder().encode(JSONValue.object(arguments))) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decodeArguments(_ raw: String) -> [String: JSONValue] {
        guard
            let data = raw.data(using: .utf8),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            let object = value.objectValue
        else { return [:] }
        return object
    }

    private func encodeResult(_ result: ToolResultPayload) -> String {
        let data = (try? JSONEncoder().encode(result)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func historyKey(_ conversationId: String) -> String {
        "whale.local.history.\(conversationId)"
    }

    private func loadHistory(_ conversationId: String) -> [DSMessage] {
        guard
            let data = UserDefaults.standard.data(forKey: historyKey(conversationId)),
            let messages = try? JSONDecoder().decode([DSMessage].self, from: data)
        else { return [] }
        return messages
    }

    private func saveHistory(_ messages: [DSMessage], for conversationId: String) {
        let trimmed = Self.trimmedHistory(messages, limit: 60)
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: historyKey(conversationId))
        }
    }

    private static func loadTurns() -> [String: LocalTurn] {
        guard
            let data = UserDefaults.standard.data(forKey: turnsKey),
            let turns = try? JSONDecoder().decode([String: LocalTurn].self, from: data)
        else { return [:] }
        return turns
    }

    private func saveTurns() {
        let trimmed = turns.suffix(5)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })) {
            UserDefaults.standard.set(data, forKey: Self.turnsKey)
        }
    }

    private static func loadTools() -> [ToolContract.Tool] {
        let url = Bundle.main.url(forResource: "tools.v1", withExtension: "json")
            ?? Bundle.main.url(forResource: "tools.v1", withExtension: "json", subdirectory: "Resources")
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let contract = try? JSONDecoder().decode(ToolContract.self, from: data)
        else { return [] }
        return contract.tools.filter { $0.name != "summarize_shared_content" }
    }

    private func loadText(_ name: String) -> String? {
        let url = Bundle.main.url(forResource: name, withExtension: "txt")
            ?? Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Resources")
        guard
            let url,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    private static func newId(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.lowercased())"
    }
}

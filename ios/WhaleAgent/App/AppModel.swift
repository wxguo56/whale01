import Foundation
import SwiftUI

enum ChatRole: Equatable {
    case user
    case assistant
    case tool
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    let text: String
    var detail: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var backendURL: String
    @Published var input = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var pending: [PendingTool] = []
    @Published private(set) var isBusy = false
    @Published private(set) var statusLine = "正在检查后端…"
    @Published private(set) var errorText: String?
    @Published private(set) var permissionsSnapshot: [String: String] = [:]
    @Published private(set) var backendExecutionMode = "unknown"

    let permissions = PermissionCenter()
    private let client = AgentClient()
    private let router: NativeToolRouter
    private var conversationId: String?
    private var activeTurnId: String?
    private var results: [String: ToolResultPayload] = [:]
    private var autoStarted: Set<String> = []

    init() {
        backendURL = UserDefaults.standard.string(forKey: BackendConfig.storageKey) ?? BackendConfig.defaultBaseURL
        router = NativeToolRouter(permissions: permissions)
        messages = [
            ChatMessage(role: .assistant, text: "我是鲸鱼。说一句话，我会在你的 iPhone 上调用真实系统能力执行。")
        ]
        permissionsSnapshot = permissions.snapshot()
    }

    func saveBackendURL() {
        let trimmed = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: BackendConfig.storageKey)
        backendURL = trimmed
        Task { await health() }
    }

    func health() async {
        do {
            let health = try await client.health()
            backendExecutionMode = health.executionMode
            statusLine = "后端 \(health.status) · 模型 \(health.modelMode) · 执行 \(health.executionMode) · 工具 \(health.tools)"
            if health.executionMode == "mock" {
                errorText = "后端当前是 mock 执行模式；要写真实系统，请用 EXECUTION_MODE=ios 启动。"
            } else if errorText?.contains("mock 执行模式") == true {
                errorText = nil
            }
        } catch {
            statusLine = "后端不可达"
            errorText = error.localizedDescription
        }
    }

    func refreshPermissions() {
        permissions.refresh()
        permissionsSnapshot = permissions.snapshot()
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        input = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: text))
        isBusy = true
        defer { isBusy = false }

        if backendExecutionMode == "unknown" {
            await health()
        }
        refreshPermissions()
        do {
            let response = try await client.startTurn(
                text: text,
                conversationId: conversationId,
                permissions: permissionsSnapshot,
                deferExecution: defersToDevice
            )
            conversationId = response.conversationId
            activeTurnId = response.turnId
            appendReplyIfNeeded(response)
            await handle(response)
        } catch {
            fail(error)
        }
    }

    func confirm(_ item: PendingTool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await executeAndCollect(item)
    }

    func skip(_ item: PendingTool) async {
        guard !isBusy else { return }
        results[item.toolCallId] = ToolResultPayload(
            toolCallId: item.toolCallId,
            status: "cancelled",
            error: ToolErrorPayload(code: "user_cancelled", message: "用户跳过了本次操作")
        )
        isBusy = true
        defer { isBusy = false }
        await submitIfComplete()
    }

    private func handle(_ response: AgentTurnResponse) async {
        switch response.status {
        case "awaiting_tool_results":
            pending = response.pending
            results = [:]
            autoStarted = []
            await startAutomaticTools()
        case "awaiting_confirmation":
            pending = response.pending
            results = [:]
        case "completed", "completed_with_limits", "failed", "cancelled", "superseded":
            pending = []
            results = [:]
            autoStarted = []
        default:
            pending = response.pending
        }
        refreshPermissions()
    }

    private func startAutomaticTools() async {
        for item in pending where !item.requiresConfirmation && !autoStarted.contains(item.toolCallId) {
            autoStarted.insert(item.toolCallId)
            await executeAndCollect(item)
        }
        await submitIfComplete()
    }

    private func executeAndCollect(_ item: PendingTool) async {
        guard results[item.toolCallId] == nil else { return }
        let result = await router.execute(item)
        results[item.toolCallId] = result
        let detail = result.error?.message ?? result.data?.displayText
        messages.append(
            ChatMessage(
                role: .tool,
                text: "\(ToolCatalog.label(item.tool)) · \(result.status)",
                detail: detail
            )
        )
        await submitIfComplete()
    }

    private func submitIfComplete() async {
        guard let turnId = activeTurnId, !pending.isEmpty else { return }
        guard pending.allSatisfy({ results[$0.toolCallId] != nil }) else { return }
        let payload = pending.compactMap { results[$0.toolCallId] }
        pending = []
        autoStarted = []
        do {
            let response = try await client.submitToolResults(turnId: turnId, results: payload)
            conversationId = response.conversationId
            activeTurnId = response.turnId
            appendReplyIfNeeded(response)
            await handle(response)
        } catch {
            fail(error)
        }
    }

    private func appendReplyIfNeeded(_ response: AgentTurnResponse) {
        guard
            let reply = response.reply?.trimmingCharacters(in: .whitespacesAndNewlines),
            !reply.isEmpty
        else {
            return
        }
        if messages.last?.role == .assistant && messages.last?.text == reply {
            return
        }
        messages.append(ChatMessage(role: .assistant, text: reply))
    }

    private func fail(_ error: Error) {
        errorText = error.localizedDescription
        messages.append(ChatMessage(role: .assistant, text: "本轮没有完成：\(error.localizedDescription)"))
    }

    private var defersToDevice: Bool {
        backendExecutionMode == "ios" || backendExecutionMode == "device"
    }
}

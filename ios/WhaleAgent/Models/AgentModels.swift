import Foundation

struct AgentTurnResponse: Codable, Sendable {
    let contractVersion: String?
    let turnId: String
    let conversationId: String
    let status: String
    let reply: String?
    let modelMode: String
    let executionMode: String
    let events: [AgentEvent]
    let pending: [PendingTool]
    let task: JSONValue?
}

struct AgentEvent: Codable, Sendable {
    let contractVersion: String?
    let eventId: String
    let turnId: String
    let conversationId: String
    let seq: Int
    let type: String
    let at: String
    let payload: JSONValue?
}

struct PendingTool: Codable, Identifiable, Sendable {
    let tool: String
    let toolCallId: String
    let operationId: String
    let arguments: [String: JSONValue]
    let requiresConfirmation: Bool

    var id: String { toolCallId }
}

struct ToolResultPayload: Codable, Sendable {
    let toolCallId: String
    let status: String
    let data: JSONValue?
    let error: ToolErrorPayload?
    let deduplicated: Bool

    init(
        toolCallId: String,
        status: String,
        data: JSONValue? = nil,
        error: ToolErrorPayload? = nil,
        deduplicated: Bool = false
    ) {
        self.toolCallId = toolCallId
        self.status = status
        self.data = data
        self.error = error
        self.deduplicated = deduplicated
    }
}

struct ToolErrorPayload: Codable, Sendable {
    let code: String
    let message: String
    let permission: String?

    init(code: String, message: String, permission: String? = nil) {
        self.code = code
        self.message = message
        self.permission = permission
    }
}

struct ToolResultSubmission: Encodable, Sendable {
    let results: [ToolResultPayload]
}

struct HealthResponse: Codable, Sendable {
    let status: String
    let modelMode: String
    let executionMode: String
    let adapterConfigured: Bool
    let tools: Int
    let requiresDeferExecution: Bool?
    let authRequired: Bool?
}

struct CachedToolOutcome: Codable, Sendable {
    let status: String
    let data: JSONValue?
    let error: ToolErrorPayload?
}

enum ToolCatalog {
    static func label(_ name: String) -> String {
        switch name {
        case "create_reminder": return "创建提醒"
        case "list_calendar_events": return "读取日历"
        case "create_calendar_event": return "创建日程"
        case "get_weather": return "查询天气"
        case "get_activity_summary": return "运动摘要"
        case "search_places": return "搜索地点"
        case "open_navigation": return "打开导航"
        case "prepare_message": return "准备短信"
        case "search_music_library": return "搜索音乐"
        case "play_music": return "播放音乐"
        case "pause_music": return "暂停音乐"
        case "resume_music": return "继续播放"
        case "skip_music_track": return "切换歌曲"
        case "get_playback_state": return "播放状态"
        case "summarize_shared_content": return "总结分享内容"
        default: return name
        }
    }

    static func summary(_ pending: PendingTool) -> String {
        let args = pending.arguments
        switch pending.tool {
        case "create_reminder":
            return [args.optionalString("title"), args.optionalString("dueAt")].compactMap { $0 }.joined(separator: " · ")
        case "create_calendar_event":
            return [args.optionalString("title"), args.optionalString("startAt")].compactMap { $0 }.joined(separator: " · ")
        case "list_calendar_events":
            return [args.optionalString("startAt"), args.optionalString("endAt")].compactMap { $0 }.joined(separator: " → ")
        case "get_weather":
            return [args.optionalString("locationName"), args.optionalString("startAt")].compactMap { $0 }.joined(separator: " · ")
        case "get_activity_summary":
            return args.optionalStringArray("metrics")?.joined(separator: "、") ?? "运动数据"
        case "search_places":
            return args.optionalString("query") ?? "附近地点"
        case "open_navigation":
            return [args.optionalString("placeId"), args.optionalString("mode")].compactMap { $0 }.joined(separator: " · ")
        case "prepare_message":
            return [args.optionalString("recipientId"), args.optionalString("body")].compactMap { $0 }.joined(separator: " · ")
        case "search_music_library":
            return [args.optionalString("query"), args.optionalString("artist")].compactMap { $0 }.joined(separator: " · ")
        case "play_music":
            return args.optionalString("trackId") ?? "当前曲目"
        case "skip_music_track":
            return args.optionalString("direction") ?? "下一首"
        default:
            return args.keys.sorted().map { "\($0)=\(args[$0]?.displayText ?? "")" }.joined(separator: "，")
        }
    }
}

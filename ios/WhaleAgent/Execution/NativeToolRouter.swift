import Foundation

@MainActor
final class NativeToolRouter {
    #if FREE_SIGNING
    private static let freeBuildUnavailableTools: Set<String> = ["get_weather", "get_activity_summary"]
    #endif

    private let permissions: PermissionCenter
    private let eventKit: EventKitExecutor
    private let health: HealthKitExecutor
    private let location: LocationExecutor
    private let message: MessageExecutor
    private let music: MusicExecutor
    private let weather: WeatherExecutor
    private let ledger: OperationLedger

    init(permissions: PermissionCenter) {
        self.permissions = permissions
        eventKit = EventKitExecutor()
        health = HealthKitExecutor()
        location = LocationExecutor()
        message = MessageExecutor()
        music = MusicExecutor()
        weather = WeatherExecutor()
        ledger = .shared
    }

    func execute(_ pending: PendingTool) async -> ToolResultPayload {
        if let cached = await ledger.outcome(for: pending.operationId) {
            return ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: cached.status,
                data: cached.data,
                error: cached.error,
                deduplicated: true
            )
        }

        #if FREE_SIGNING
        if Self.freeBuildUnavailableTools.contains(pending.tool) {
            return ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: "failed",
                error: ToolErrorPayload(
                    code: "unavailable_in_free_build",
                    message: "免费签名版不包含 HealthKit / WeatherKit 能力，本次未执行；请改用提醒、日历、地点、音乐等能力。"
                )
            )
        }
        #endif

        if let missing = await permissions.ensure(tool: pending.tool) {
            return ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: "needs_authorization",
                error: ToolErrorPayload(
                    code: "permission_denied",
                    message: "需要先授权\(PermissionCenter.label(missing))，本次未执行",
                    permission: missing
                )
            )
        }

        do {
            let data = try await route(pending)
            let result = ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: "success",
                data: data
            )
            await ledger.record(
                operationId: pending.operationId,
                outcome: CachedToolOutcome(status: result.status, data: result.data, error: result.error)
            )
            return result
        } catch let error as ToolExecutionError {
            return ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: error.status,
                error: ToolErrorPayload(
                    code: error.code,
                    message: error.message,
                    permission: error.permission
                )
            )
        } catch {
            return ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: "failed",
                error: ToolErrorPayload(
                    code: "native_execution_failed",
                    message: error.localizedDescription
                )
            )
        }
    }

    func listCalendarEvents(startAt: Date, endAt: Date) throws -> JSONValue {
        try eventKit.listCalendarEvents(arguments: [
            "startAt": .string(ToolDate.iso(startAt)),
            "endAt": .string(ToolDate.iso(endAt)),
            "calendarIds": .array([])
        ])
    }

    func searchMusic(query: String?) async throws -> JSONValue {
        var arguments: [String: JSONValue] = ["limit": .number(25)]
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { arguments["query"] = .string(trimmed) }
        }
        return try await music.search(arguments: arguments)
    }

    func playMusic(trackId: String) async throws -> JSONValue {
        try await music.play(arguments: ["trackId": .string(trackId)])
    }

    func pauseMusic() async throws -> JSONValue {
        try await music.pause(arguments: [:])
    }

    func resumeMusic() async throws -> JSONValue {
        try await music.resume(arguments: [:])
    }

    func skipMusic(direction: String) async throws -> JSONValue {
        try await music.skip(arguments: ["direction": .string(direction)])
    }

    func playbackState() async throws -> JSONValue {
        try await music.playbackState(arguments: [:])
    }

    private func route(_ pending: PendingTool) async throws -> JSONValue {
        switch pending.tool {
        case "create_reminder":
            return try await eventKit.createReminder(arguments: pending.arguments, operationId: pending.operationId)
        case "list_calendar_events":
            return try eventKit.listCalendarEvents(arguments: pending.arguments)
        case "create_calendar_event":
            return try eventKit.createCalendarEvent(arguments: pending.arguments, operationId: pending.operationId)
        case "get_weather":
            return try await weather.query(arguments: pending.arguments)
        case "get_activity_summary":
            return try await health.summary(arguments: pending.arguments)
        case "search_places":
            return try await location.searchPlaces(arguments: pending.arguments)
        case "open_navigation":
            return try location.openNavigation(arguments: pending.arguments)
        case "prepare_message":
            return try await message.prepare(arguments: pending.arguments)
        case "search_music_library":
            return try await music.search(arguments: pending.arguments)
        case "play_music":
            return try await music.play(arguments: pending.arguments)
        case "pause_music":
            return try await music.pause(arguments: pending.arguments)
        case "resume_music":
            return try await music.resume(arguments: pending.arguments)
        case "skip_music_track":
            return try await music.skip(arguments: pending.arguments)
        case "get_playback_state":
            return try await music.playbackState(arguments: pending.arguments)
        default:
            throw ToolExecutionError(
                code: "unsupported_tool",
                message: "手机执行器不支持 \(pending.tool)；该工具应由后端处理"
            )
        }
    }
}

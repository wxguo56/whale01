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
    private let web: WebContentExecutor
    private let merchantPrice: MerchantPriceExecutor
    private let ledger: OperationLedger

    private static let executionTimeout: Double = 20

    init(permissions: PermissionCenter) {
        self.permissions = permissions
        eventKit = EventKitExecutor()
        health = HealthKitExecutor()
        location = LocationExecutor()
        message = MessageExecutor()
        music = MusicExecutor()
        weather = WeatherExecutor()
        let webExecutor = WebContentExecutor()
        web = webExecutor
        merchantPrice = MerchantPriceExecutor(web: webExecutor)
        ledger = .shared
    }

    func execute(_ pending: PendingTool) async -> ToolResultPayload {
        let result = await executeInternal(pending)
        await recordAction(pending, result: result)
        return result
    }

    private func executeInternal(_ pending: PendingTool) async -> ToolResultPayload {
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

        if let missing = await permissions.ensure(tool: pending.tool, arguments: pending.arguments) {
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

        if let write = pendingWrite(for: pending) {
            await ledger.markPending(write)
        }

        do {
            let data = try await withTimeout(seconds: Self.executionTimeout) {
                try await self.route(pending)
            }
            let result = ToolResultPayload(
                toolCallId: pending.toolCallId,
                status: "success",
                data: data,
                deduplicated: data.objectValue?.optionalBool("deduplicated") ?? false
            )
            await ledger.resolvePending(
                operationId: pending.operationId,
                outcome: CachedToolOutcome(status: result.status, data: result.data, error: result.error)
            )
            return result
        } catch let error as ToolExecutionError {
            if error.code != "execution_unknown" {
                await ledger.resolvePending(
                    operationId: pending.operationId,
                    outcome: CachedToolOutcome(
                        status: error.status,
                        data: nil,
                        error: ToolErrorPayload(code: error.code, message: error.message, permission: error.permission)
                    )
                )
            }
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
            await ledger.resolvePending(
                operationId: pending.operationId,
                outcome: CachedToolOutcome(
                    status: "failed",
                    data: nil,
                    error: ToolErrorPayload(code: "native_execution_failed", message: error.localizedDescription)
                )
            )
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

    private func recordAction(_ pending: PendingTool, result: ToolResultPayload) async {
        let detail = ToolPresentation.resultDetail(
            tool: pending.tool,
            status: result.status,
            data: result.data,
            error: result.error
        )
        await ledger.recordAction(
            OperationRecord(
                id: pending.operationId,
                tool: pending.tool,
                status: result.status,
                title: ToolPresentation.title(pending.tool),
                detail: detail,
                source: pending.source ?? "chat"
            )
        )
    }

    private func pendingWrite(for pending: PendingTool) -> PendingWrite? {
        let arguments = pending.arguments
        switch pending.tool {
        case "create_reminder":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("title") ?? "",
                dueAt: arguments.optionalString("dueAt"),
                startAt: nil,
                createdAt: Date(),
                action: "create"
            )
        case "create_calendar_event":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("title") ?? "",
                dueAt: nil,
                startAt: arguments.optionalString("startAt"),
                createdAt: Date(),
                action: "create"
            )
        case "update_reminder":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("newTitle") ?? arguments.optionalString("title") ?? "",
                dueAt: arguments.optionalString("dueAt"),
                startAt: nil,
                createdAt: Date(),
                action: "update",
                recordId: arguments.optionalString("recordId")
            )
        case "delete_reminder":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("title") ?? "",
                dueAt: arguments.optionalString("dueAt"),
                startAt: nil,
                createdAt: Date(),
                action: "delete",
                recordId: arguments.optionalString("recordId")
            )
        case "update_calendar_event":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("title") ?? "",
                dueAt: nil,
                startAt: arguments.optionalString("startAt"),
                createdAt: Date(),
                action: "update",
                recordId: arguments.optionalString("eventId")
            )
        case "delete_calendar_event":
            return PendingWrite(
                operationId: pending.operationId,
                tool: pending.tool,
                title: arguments.optionalString("title") ?? "",
                dueAt: nil,
                startAt: nil,
                createdAt: Date(),
                action: "delete",
                recordId: arguments.optionalString("eventId")
            )
        default:
            return nil
        }
    }

    func reconcileUnknownWrites() async -> [String] {
        let writes = await ledger.listPendingWrites()
        var notes: [String] = []
        for write in writes {
            let age = Date().timeIntervalSince(write.createdAt)
            switch write.tool {
            case "create_reminder":
                guard !write.title.isEmpty else { continue }
                let due = write.dueAt.flatMap { ToolDate.parse($0) }
                if let id = await eventKit.findReminder(title: write.title, dueAt: due) {
                    let data = JSONValue.object([
                        "recordId": .string(id),
                        "title": .string(write.title),
                        "source": .string("eventkit"),
                        "reconciled": .bool(true)
                    ])
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(status: "success", data: data, error: nil)
                    )
                    notes.append("已核对：提醒「\(write.title)」实际已写入系统，未重复创建。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "reconciled_absent", message: "核对后未发现该提醒")
                        )
                    )
                    notes.append("已核对：未发现提醒「\(write.title)」，可以重新发起。")
                }
            case "create_calendar_event":
                guard !write.title.isEmpty, let rawStart = write.startAt, let start = ToolDate.parse(rawStart) else {
                    continue
                }
                if let id = eventKit.findCalendarEvent(title: write.title, startAt: start) {
                    let data = JSONValue.object([
                        "eventId": .string(id),
                        "title": .string(write.title),
                        "source": .string("eventkit"),
                        "reconciled": .bool(true)
                    ])
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(status: "success", data: data, error: nil)
                    )
                    notes.append("已核对：日程「\(write.title)」实际已写入系统，未重复创建。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "reconciled_absent", message: "核对后未发现该日程")
                        )
                    )
                    notes.append("已核对：未发现日程「\(write.title)」，可以重新发起。")
                }
            case "update_reminder":
                let stillExists: Bool
                if let recordId = write.recordId, !recordId.isEmpty {
                    stillExists = eventKit.reminderExists(recordId: recordId)
                } else {
                    let due = write.dueAt.flatMap { ToolDate.parse($0) }
                    if write.title.isEmpty {
                        stillExists = false
                    } else {
                        stillExists = await eventKit.findReminder(title: write.title, dueAt: due) != nil
                    }
                }
                if !stillExists {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "reminder_not_found", message: "核对后没有找到要修改的提醒")
                        )
                    )
                    notes.append("已核对：未找到要修改的提醒，可能已被删除。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "execution_unknown",
                            data: nil,
                            error: ToolErrorPayload(
                                code: "execution_unknown",
                                message: "提醒仍存在，但无法确认修改是否已生效，请先在提醒事项中核对，不要直接重试。"
                            )
                        )
                    )
                    notes.append("已核对：提醒仍存在，但修改结果无法自动确认，请打开系统核对。")
                }
            case "delete_reminder":
                let stillExists: Bool
                if let recordId = write.recordId, !recordId.isEmpty {
                    stillExists = eventKit.reminderExists(recordId: recordId)
                } else {
                    let due = write.dueAt.flatMap { ToolDate.parse($0) }
                    if write.title.isEmpty {
                        stillExists = false
                    } else {
                        stillExists = await eventKit.findReminder(title: write.title, dueAt: due) != nil
                    }
                }
                if !stillExists {
                    let data = JSONValue.object([
                        "recordId": .string(write.recordId ?? ""),
                        "deleted": .bool(true),
                        "source": .string("eventkit"),
                        "reconciled": .bool(true)
                    ])
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(status: "success", data: data, error: nil)
                    )
                    notes.append("已核对：该提醒已不存在，删除实际已生效。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "delete_not_applied", message: "提醒仍然存在，删除未生效")
                        )
                    )
                    notes.append("已核对：提醒仍然存在，删除未生效，可以重新发起。")
                }
            case "update_calendar_event":
                let stillExists: Bool
                if let eventId = write.recordId, !eventId.isEmpty {
                    stillExists = eventKit.calendarEventExists(eventId: eventId)
                } else {
                    stillExists = false
                }
                if !stillExists {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "event_not_found", message: "核对后没有找到要修改的日程")
                        )
                    )
                    notes.append("已核对：未找到要修改的日程，可能已被删除。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "execution_unknown",
                            data: nil,
                            error: ToolErrorPayload(
                                code: "execution_unknown",
                                message: "日程仍存在，但无法确认修改是否已生效，请先在日历中核对，不要直接重试。"
                            )
                        )
                    )
                    notes.append("已核对：日程仍存在，但修改结果无法自动确认，请打开系统日历核对。")
                }
            case "delete_calendar_event":
                let stillExists: Bool
                if let eventId = write.recordId, !eventId.isEmpty {
                    stillExists = eventKit.calendarEventExists(eventId: eventId)
                } else {
                    stillExists = false
                }
                if !stillExists {
                    let data = JSONValue.object([
                        "eventId": .string(write.recordId ?? ""),
                        "deleted": .bool(true),
                        "source": .string("eventkit"),
                        "reconciled": .bool(true)
                    ])
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(status: "success", data: data, error: nil)
                    )
                    notes.append("已核对：该日程已不存在，删除实际已生效。")
                } else if age > 120 {
                    await ledger.resolvePending(
                        operationId: write.operationId,
                        outcome: CachedToolOutcome(
                            status: "failed",
                            data: nil,
                            error: ToolErrorPayload(code: "delete_not_applied", message: "日程仍然存在，删除未生效")
                        )
                    )
                    notes.append("已核对：日程仍然存在，删除未生效，可以重新发起。")
                }
            default:
                continue
            }
        }
        return notes
    }

    /// Stops waiting for a system operation instead of leaving the turn stuck forever.
    /// A timed-out write is reported as `execution_unknown`: the system may already
    /// have applied it, so the caller must verify before retrying.
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let box = TimeoutBox<T>()
        return try await withCheckedThrowingContinuation { continuation in
            box.attach(continuation)
            Task {
                do {
                    let value = try await operation()
                    box.finish(.success(value))
                } catch {
                    box.finish(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                box.finish(.failure(ToolExecutionError(
                    code: "execution_unknown",
                    message: "设备操作超过 \(Int(seconds)) 秒仍未返回，已停止等待。结果可能已经生效，请先到系统 App 中核对，不要直接重试。"
                )))
            }
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

    private func listMemories() -> JSONValue {
        let rows = MemoryStore.shared.list().map { preference in
            JSONValue.object([
                "id": .string(preference.id),
                "key": .string(preference.key),
                "value": .string(preference.value),
                "updatedAt": .string(ToolDate.iso(preference.updatedAt))
            ])
        }
        return .object([
            "memories": .array(rows),
            "count": .number(Double(rows.count)),
            "source": .string("memory"),
            "note": .string("偏好只用于建议，不构成长期操作授权")
        ])
    }

    private func setMemory(_ arguments: [String: JSONValue]) throws -> JSONValue {
        let key = try arguments.requiredString("key")
        let value = try arguments.requiredString("value")
        do {
            let preference = try MemoryStore.shared.set(key: key, value: value)
            return .object([
                "id": .string(preference.id),
                "key": .string(preference.key),
                "value": .string(preference.value),
                "updatedAt": .string(ToolDate.iso(preference.updatedAt)),
                "source": .string("memory"),
                "note": .string("已保存为可编辑偏好，不是长期操作授权")
            ])
        } catch {
            throw ToolExecutionError(code: "memory_invalid", message: error.localizedDescription)
        }
    }

    private func deleteMemory(_ arguments: [String: JSONValue]) throws -> JSONValue {
        let id = arguments.optionalString("id") ?? arguments.optionalString("key")
        guard let id, !id.isEmpty else {
            throw ToolExecutionError(code: "missing_memory_reference", message: "需要偏好 id 或 key")
        }
        let deleted = MemoryStore.shared.delete(id: id)
        return .object([
            "id": .string(id),
            "deleted": .bool(deleted),
            "source": .string("memory")
        ])
    }

    private func route(_ pending: PendingTool) async throws -> JSONValue {
        switch pending.tool {
        case "create_reminder":
            return try await eventKit.createReminder(arguments: pending.arguments, operationId: pending.operationId)
        case "list_reminders":
            return try await eventKit.listReminders(arguments: pending.arguments)
        case "update_reminder":
            return try await eventKit.updateReminder(arguments: pending.arguments)
        case "delete_reminder":
            return try await eventKit.deleteReminder(arguments: pending.arguments)
        case "list_calendar_events":
            return try eventKit.listCalendarEvents(arguments: pending.arguments)
        case "find_free_slots":
            return try eventKit.findFreeSlots(arguments: pending.arguments)
        case "create_calendar_event":
            return try eventKit.createCalendarEvent(arguments: pending.arguments, operationId: pending.operationId)
        case "update_calendar_event":
            return try eventKit.updateCalendarEvent(arguments: pending.arguments)
        case "delete_calendar_event":
            return try eventKit.deleteCalendarEvent(arguments: pending.arguments)
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
        case "list_memory":
            return listMemories()
        case "set_memory":
            return try setMemory(pending.arguments)
        case "delete_memory":
            return try deleteMemory(pending.arguments)
        case "search_web":
            return try await web.search(
                query: try pending.arguments.requiredString("query"),
                limit: pending.arguments.optionalInt("limit") ?? 6
            )
        case "fetch_web_content":
            return try await web.fetch(
                urlString: try pending.arguments.requiredString("url"),
                maxChars: pending.arguments.optionalInt("maxChars") ?? 6000
            )
        case "search_merchant_prices":
            return try await merchantPrice.search(arguments: pending.arguments)
        case "summarize_shared_content":
            throw ToolExecutionError(
                code: "use_share_entry",
                message: "分享内容由 App 的分享入口直接处理；本机模式不单独调用摘要工具"
            )
        default:
            throw ToolExecutionError(
                code: "unsupported_tool",
                message: "手机执行器不支持 \(pending.tool)；该工具应由后端处理"
            )
        }
    }
}

/// Resumes exactly one continuation: either the system operation or the timeout wins.
private final class TimeoutBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var finished = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

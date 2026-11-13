import Foundation

@MainActor
final class NativeToolRouter {
    static let freeBuildUnavailableTools: Set<String> = ["get_activity_summary"]

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
    private let discover = DiscoverClient()

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

    func calendarPreview(_ pending: PendingTool) async throws -> CalendarWritePreview? {
        guard ["create_calendar_event", "update_calendar_event"].contains(pending.tool) else { return nil }
        if let missing = await permissions.ensure(tool: "list_calendar_events", arguments: pending.arguments) {
            throw ToolExecutionError(code: "permission_denied", message: "需要日历读取权限才能核对冲突。", permission: missing)
        }
        return try eventKit.calendarPreview(arguments: pending.arguments)
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
                    message: "免费签名无法启用 HealthKit（需要 Apple 开发者团队的 HealthKit 授权），本次未执行运动摘要；天气查询已改用公共接口，不受影响。请改用提醒、日历、地点、天气、音乐等能力。"
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
                            status: "execution_unknown",
                            data: nil,
                            error: ToolErrorPayload(code: "execution_unknown", message: "暂未发现提醒，无法排除权限或同步问题，请先在系统核对。")
                        )
                    )
                    notes.append("已核对：未发现提醒「\(write.title)」，请先在系统核对，未自动重放。")
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
                            status: "execution_unknown",
                            data: nil,
                            error: ToolErrorPayload(code: "execution_unknown", message: "暂未发现日程，无法排除权限或同步问题，请先在系统核对。")
                        )
                    )
                    notes.append("已核对：未发现日程「\(write.title)」，请先在系统核对，未自动重放。")
                }
            case "update_reminder", "delete_reminder", "update_calendar_event", "delete_calendar_event":
                guard age > 120 else { continue }
                let presence: SystemRecordPresence = write.tool.contains("reminder")
                    ? eventKit.reminderPresence(recordId: write.recordId ?? "")
                    : eventKit.calendarEventPresence(eventId: write.recordId ?? "")
                let detail: String
                switch presence {
                case .present: detail = "目标仍存在，但无法确认上次修改或删除的结果。"
                case .missing: detail = "当前没有查到目标；账号同步或标识变化也可能造成缺失，不能据此认定删除成功。"
                case .unobservable: detail = "当前没有完整权限或稳定目标标识，无法核对上次结果。"
                }
                await ledger.resolvePending(operationId: write.operationId, outcome: CachedToolOutcome(
                    status: "execution_unknown", data: nil,
                    error: ToolErrorPayload(code: "execution_unknown", message: detail + "请到系统核对，勿直接重试。")
                ))
                notes.append(detail + "请到系统核对，未自动重放操作。")
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

    func listReminders(includeCompleted: Bool) async throws -> JSONValue {
        try await eventKit.listReminders(arguments: [
            "includeCompleted": .bool(includeCompleted),
            "timezone": .string(TimeZone.current.identifier),
            "limit": .number(100)
        ])
    }

    func createReminder(title: String, dueAt: Date? = nil, notes: String? = nil) async throws -> JSONValue {
        var arguments: [String: JSONValue] = [
            "title": .string(title),
            "timezone": .string(TimeZone.current.identifier)
        ]
        if let dueAt {
            arguments["dueAt"] = .string(ToolDate.iso(dueAt))
        }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments["notes"] = .string(notes)
        }
        return try await eventKit.createReminder(
            arguments: arguments,
            operationId: "todo-ui-\(UUID().uuidString)"
        )
    }

    func updateReminder(recordId: String, completed: Bool) async throws -> JSONValue {
        try await eventKit.updateReminder(arguments: [
            "recordId": .string(recordId),
            "completed": .bool(completed),
            "timezone": .string(TimeZone.current.identifier)
        ])
    }

    func deleteReminder(recordId: String) async throws -> JSONValue {
        try await eventKit.deleteReminder(arguments: [
            "recordId": .string(recordId)
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

    func playMusicAlbum(albumId: String) async throws -> JSONValue {
        try await music.playAlbum(albumId: albumId)
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
        let deleted = try MemoryStore.shared.delete(id: id)
        return .object([
            "id": .string(id),
            "deleted": .bool(deleted),
            "source": .string("memory")
        ])
    }

    private func addWatchlist(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let stock = try await resolveStock(query)
        let added = WatchlistStore.shared.add(stock.symbol)
        return watchlistPayload(stock: stock, added: added, removed: false)
    }

    private func removeWatchlist(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let stock = try await resolveStock(query)
        let removed = WatchlistStore.shared.remove(stock.symbol)
        return watchlistPayload(stock: stock, added: false, removed: removed)
    }

    private func listWatchlist() async throws -> JSONValue {
        let symbols = WatchlistStore.shared.symbols
        var names: [String: (name: String, code: String, market: String)] = [:]
        if !symbols.isEmpty, let response = try? await discover.quotes(symbols: symbols) {
            for quote in response.quotes {
                names[quote.symbol] = (quote.name, quote.code, quote.market)
            }
        }
        let items = symbols.map { symbol -> JSONValue in
            let info = names[symbol]
            return .object([
                "symbol": .string(symbol),
                "name": .string(info?.name ?? symbol),
                "code": .string(info?.code ?? symbol),
                "market": .string(info?.market ?? ""),
                "resolved": .bool(info != nil)
            ])
        }
        return .object([
            "count": .number(Double(symbols.count)),
            "items": .array(items),
            "source": .string("本机自选列表")
        ])
    }

    private func resolveStock(_ raw: String) async throws -> StockSearchResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ToolExecutionError(code: "invalid_arguments", message: "股票名称或代码不能为空")
        }
        if text.range(of: "^(sh|sz|bj)[0-9]{6}$", options: [.regularExpression, .caseInsensitive]) != nil {
            let response = try await discover.quotes(symbols: [text.lowercased()])
            if let quote = response.quotes.first {
                return StockSearchResult(
                    symbol: quote.symbol,
                    code: quote.code,
                    name: quote.name,
                    market: quote.market,
                    type: "stock"
                )
            }
            throw ToolExecutionError(code: "symbol_not_found", message: "没有取到 \(text) 的行情，无法确认这只股票，本次未写入自选")
        }

        let response = try await discover.search(text)
        if response.results.isEmpty {
            throw ToolExecutionError(code: "stock_not_found", message: "没有找到「\(text)」对应的 A 股或指数，本次未写入自选")
        }
        let exact = response.results.filter { $0.name == text || $0.code == text }
        if exact.count == 1 { return exact[0] }
        if response.results.count == 1 { return response.results[0] }
        let candidates = response.results.prefix(5)
            .map { "\($0.name)（\($0.symbol)）" }
            .joined(separator: "、")
        throw ToolExecutionError(
            code: "ambiguous_stock",
            message: "「\(text)」匹配到多只股票：\(candidates)。请先让用户确认具体哪一只，本次未写入自选"
        )
    }

    private func watchlistPayload(stock: StockSearchResult, added: Bool, removed: Bool) -> JSONValue {
        let symbols = WatchlistStore.shared.symbols
        let message: String
        if removed {
            message = "已从本机自选移除 \(stock.name)"
        } else if added {
            message = "已将 \(stock.name) 加入本机自选"
        } else {
            message = "\(stock.name) 已在本机自选中，没有重复写入"
        }
        return .object([
            "symbol": .string(stock.symbol),
            "code": .string(stock.code),
            "name": .string(stock.name),
            "market": .string(stock.market),
            "added": .bool(added),
            "removed": .bool(removed),
            "watchlistCount": .number(Double(symbols.count)),
            "watchlist": .array(symbols.map { .string($0) }),
            "message": .string(message),
            "source": .string("本机自选；行情仍需后端公开延迟报价")
        ])
    }

    // MARK: - Public research tools

    private func techNews(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let rawChannel = arguments.optionalString("channel") ?? "ai"
        guard let channel = DiscoverChannel(rawValue: rawChannel),
              channel == .ai || channel == .headline || channel == .game else {
            throw ToolExecutionError(code: "invalid_arguments", message: "channel 只能是 ai、headline 或 game")
        }
        let limit = min(max(arguments.optionalInt("limit") ?? 8, 1), 12)
        let response = try await discover.news(channel: channel, limit: limit)
        return .object([
            "channel": .string(response.channel),
            "updatedAt": .string(response.updatedAt),
            "sources": .array((response.sources ?? []).map { .string($0) }),
            "unavailableSources": .array((response.unavailableSources ?? []).map { .string($0) }),
            "items": .array(response.items.prefix(limit).map(newsJSON))
        ])
    }

    private func gameRank(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let rawBoard = arguments.optionalString("board") ?? "free"
        guard let board = GameRankBoard(rawValue: rawBoard) else {
            throw ToolExecutionError(code: "invalid_arguments", message: "board 只能是 free 或 grossing")
        }
        let limit = min(max(arguments.optionalInt("limit") ?? 20, 1), 50)
        let response = try await discover.gameRank(board: board, limit: limit)
        return .object([
            "board": .string(response.board),
            "boardName": .string(response.boardName),
            "updatedAt": .string(response.updatedAt),
            "source": .string(response.source),
            "note": .string(response.note ?? ""),
            "items": .array(response.items.map { item -> JSONValue in
                .object([
                    "rank": .number(Double(item.rank)),
                    "id": .string(item.id),
                    "name": .string(item.name),
                    "artist": .string(item.artist),
                    "category": .string(item.category),
                    "icon": .string(item.icon),
                    "releaseDate": .string(item.releaseDate),
                    "link": .string(item.link)
                ])
            })
        ])
    }

    private func stockQuote(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let stock = try await resolveStock(query)
        let response = try await discover.quotes(symbols: [stock.symbol])
        return .object([
            "query": .string(query),
            "updatedAt": .string(response.updatedAt),
            "delayedMinutes": response.delayedMinutes.map { .number(Double($0)) } ?? .null,
            "source": .string(response.source),
            "quotes": .array(response.quotes.map(quoteJSON))
        ])
    }

    private func searchStock(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let response = try await discover.search(query)
        return .object([
            "query": .string(response.query),
            "source": .string(response.source),
            "results": .array(response.results.map(searchJSON))
        ])
    }

    private func stockKline(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let stock = try await resolveStock(query)
        let days = min(max(arguments.optionalInt("days") ?? 120, 5), 500)
        let response = try await discover.kline(symbol: stock.symbol, days: days)
        return .object([
            "symbol": .string(response.symbol),
            "code": .string(response.code),
            "name": .string(response.name),
            "days": .number(Double(response.days)),
            "fetchedAt": .string(ToolDate.iso(Date())),
            "source": .string(response.source),
            "delayedMinutes": response.delayedMinutes.map { .number(Double($0)) } ?? .null,
            "points": .array(response.points.map(klineJSON))
        ])
    }

    private func stockIntraday(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let stock = try await resolveStock(query)
        let response = try await discover.intraday(symbol: stock.symbol)
        return .object([
            "symbol": .string(response.symbol),
            "code": .string(response.code),
            "name": .string(response.name),
            "date": .string(response.date),
            "fetchedAt": .string(ToolDate.iso(Date())),
            "source": .string(response.source),
            "delayedMinutes": response.delayedMinutes.map { .number(Double($0)) } ?? .null,
            "points": .array(response.points.map(intradayJSON))
        ])
    }

    private func newsJSON(_ item: NewsItem) -> JSONValue {
        .object([
            "id": .string(item.id),
            "title": .string(item.title),
            "summary": .string(item.summary),
            "source": .string(item.source),
            "link": .string(item.link),
            "publishedAt": item.publishedAt.map(JSONValue.string) ?? .null,
            "fetchedAt": item.fetchedAt.map(JSONValue.string) ?? .null,
            "channel": .string(item.channel),
            "rank": jsonNumber(item.rank.map { Double($0) })
        ])
    }

    private func quoteJSON(_ quote: StockQuote) -> JSONValue {
        .object([
            "symbol": .string(quote.symbol),
            "code": .string(quote.code),
            "market": .string(quote.market),
            "name": .string(quote.name),
            "price": jsonNumber(quote.price),
            "previousClose": jsonNumber(quote.previousClose),
            "open": jsonNumber(quote.open),
            "high": jsonNumber(quote.high),
            "low": jsonNumber(quote.low),
            "change": jsonNumber(quote.change),
            "changePercent": jsonNumber(quote.changePercent),
            "volumeLots": jsonNumber(quote.volumeLots),
            "volume": jsonNumber(quote.volume),
            "amount": jsonNumber(quote.amount),
            "turnoverPercent": jsonNumber(quote.turnoverPercent),
            "pe": jsonNumber(quote.pe),
            "marketCap": jsonNumber(quote.marketCap),
            "floatMarketCap": jsonNumber(quote.floatMarketCap),
            "timestamp": jsonText(quote.timestamp),
            "source": .string(quote.source ?? "腾讯财经公开行情"),
            "delayedMinutes": quote.delayedMinutes.map { .number(Double($0)) } ?? .null
        ])
    }

    private func searchJSON(_ result: StockSearchResult) -> JSONValue {
        .object([
            "symbol": .string(result.symbol),
            "code": .string(result.code),
            "name": .string(result.name),
            "market": .string(result.market),
            "type": .string(result.type)
        ])
    }

    private func klineJSON(_ point: KlinePoint) -> JSONValue {
        .object([
            "date": .string(point.date),
            "open": jsonNumber(point.open),
            "close": jsonNumber(point.close),
            "high": jsonNumber(point.high),
            "low": jsonNumber(point.low),
            "volume": jsonNumber(point.volume),
            "volumeLots": jsonNumber(point.volumeLots),
            "amount": jsonNumber(point.amount)
        ])
    }

    private func intradayJSON(_ point: IntradayPoint) -> JSONValue {
        .object([
            "time": .string(point.time),
            "price": jsonNumber(point.price),
            "volumeLots": jsonNumber(point.volumeLots),
            "amount": jsonNumber(point.amount)
        ])
    }

    private func jsonNumber(_ value: Double?) -> JSONValue {
        value.map { .number($0) } ?? .null
    }

    private func jsonText(_ value: String?) -> JSONValue {
        value.map { .string($0) } ?? .null
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
        case "get_current_location":
            return try await location.currentPlace(arguments: pending.arguments)
        case "open_navigation":
            return try location.openNavigation(arguments: pending.arguments)
        case "prepare_message":
            return try await message.prepare(arguments: pending.arguments)
        case "search_music_library":
            return try await music.search(arguments: pending.arguments)
        case "play_music":
            return try await music.play(arguments: pending.arguments)
        case "play_music_album":
            return try await music.play(arguments: pending.arguments)
        case "open_netease_music":
            return try await music.openNetEase(arguments: pending.arguments)
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
        case "add_to_watchlist":
            return try await addWatchlist(pending.arguments)
        case "remove_from_watchlist":
            return try await removeWatchlist(pending.arguments)
        case "list_watchlist":
            return try await listWatchlist()
        case "get_tech_news":
            return try await techNews(pending.arguments)
        case "get_game_rank":
            return try await gameRank(pending.arguments)
        case "get_stock_quote":
            return try await stockQuote(pending.arguments)
        case "search_stock":
            return try await searchStock(pending.arguments)
        case "get_stock_kline":
            return try await stockKline(pending.arguments)
        case "get_stock_intraday":
            return try await stockIntraday(pending.arguments)
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

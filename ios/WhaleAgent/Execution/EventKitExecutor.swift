import EventKit
import Foundation

@MainActor
final class EventKitExecutor {
    private let store = EKEventStore()

    func createReminder(arguments: [String: JSONValue], operationId: String) async throws -> JSONValue {
        let title = try arguments.requiredString("title")
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier

        let dueDate: Date?
        if let rawDueAt = arguments.optionalString("dueAt") {
            guard let parsed = ToolDate.parse(rawDueAt) else {
                throw ToolExecutionError(code: "invalid_due_at", message: "dueAt 无法解析")
            }
            dueDate = parsed
        } else {
            dueDate = nil
        }

        let calendar = try resolveReminderCalendar(arguments.optionalString("listId"))

        let recurrence = try recurrenceRule(from: arguments)
        if recurrence != nil, dueDate == nil {
            throw ToolExecutionError(code: "invalid_recurrence", message: "重复提醒需要具体的开始时间")
        }
        if recurrence == nil,
           let existingId = await existingReminderId(title: title, dueDate: dueDate, calendar: calendar) {
            var row: [String: JSONValue] = [
                "recordId": .string(existingId),
                "title": .string(title),
                "dueAt": dueDate.map { JSONValue.string(ToolDate.iso($0)) } ?? .null,
                "timezone": .string(timezone),
                "listName": .string(calendar.title),
                "source": .string("eventkit"),
                "simulated": .bool(false),
                "deduplicated": .bool(true),
                "note": .string("已存在相同提醒，未重复创建")
            ]
            row["operationId"] = .string(operationId)
            return .object(row)
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = arguments.optionalString("notes")
        reminder.calendar = calendar
        if let recurrence {
            reminder.addRecurrenceRule(recurrence)
        }

        if let dueDate {
            var components = ToolDate.calendar(timezone).dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueDate
            )
            components.timeZone = ToolDate.zone(timezone)
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        try store.save(reminder, commit: true)

        var row: [String: JSONValue] = [
            "recordId": .string(reminder.calendarItemIdentifier),
            "title": .string(title),
            "dueAt": dueDate.map { JSONValue.string(ToolDate.iso($0)) } ?? .null,
            "timezone": .string(timezone),
            "listName": .string(calendar.title),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ]
        if let label = recurrenceLabel(from: arguments) {
            row["recurrence"] = .string(label)
        }
        row["operationId"] = .string(operationId)
        return .object(row)
    }

    func listReminders(arguments: [String: JSONValue]) async throws -> JSONValue {
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier
        let calendar = arguments.optionalString("listId").flatMap { store.calendar(withIdentifier: $0) }
        let calendars: [EKCalendar]? = calendar.map { [$0] }
        let reminders = await fetchReminders(calendars: calendars)
        let includeCompleted = arguments.optionalBool("includeCompleted") ?? false
        let start = arguments.optionalString("startAt").flatMap(ToolDate.parse)
        let end = arguments.optionalString("endAt").flatMap(ToolDate.parse)
        let limit = max(1, min(arguments.optionalInt("limit") ?? 50, 100))
        let dueCalendar = ToolDate.calendar(timezone)

        let filtered = reminders.filter { reminder in
            if !includeCompleted && reminder.isCompleted { return false }
            guard start != nil || end != nil else { return true }
            guard let due = reminder.dueDateComponents.flatMap({ dueCalendar.date(from: $0) }) else { return false }
            if let start, due < start { return false }
            if let end, due >= end { return false }
            return true
        }.sorted { left, right in
            let leftDate = left.dueDateComponents.flatMap { dueCalendar.date(from: $0) }
            let rightDate = right.dueDateComponents.flatMap { dueCalendar.date(from: $0) }
            switch (leftDate, rightDate) {
            case let (leftDate?, rightDate?): return leftDate < rightDate
            case (_?, nil): return true
            default: return false
            }
        }

        let rows = filtered.prefix(limit).map { JSONValue.object(reminderPayload($0, timezone: timezone)) }
        return .object([
            "reminders": .array(Array(rows)),
            "count": .number(Double(rows.count)),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ])
    }

    func updateReminder(arguments: [String: JSONValue]) async throws -> JSONValue {
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier
        let reminder = try await resolveReminder(arguments)

        let recordId = arguments.optionalString("recordId")
        if let newTitle = arguments.optionalString("newTitle"),
           !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reminder.title = newTitle
        } else if let recordId, !recordId.isEmpty,
                  let title = arguments.optionalString("title"),
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reminder.title = title
        }
        if let notes = arguments.optionalString("notes") {
            reminder.notes = notes
        }
        if let rawDueAt = arguments.optionalString("dueAt") {
            guard let dueDate = ToolDate.parse(rawDueAt) else {
                throw ToolExecutionError(code: "invalid_due_at", message: "dueAt 无法解析")
            }
            var components = ToolDate.calendar(timezone).dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueDate
            )
            components.timeZone = ToolDate.zone(timezone)
            reminder.dueDateComponents = components
            reminder.alarms = [EKAlarm(absoluteDate: dueDate)]
        }
        if let completed = arguments.optionalBool("completed") {
            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil
        }
        if let listId = arguments.optionalString("listId"),
           let calendar = store.calendar(withIdentifier: listId),
           calendar.allowsContentModifications {
            reminder.calendar = calendar
        }

        try store.save(reminder, commit: true)
        return .object(reminderPayload(reminder, timezone: timezone))
    }

    func deleteReminder(arguments: [String: JSONValue]) async throws -> JSONValue {
        let reminder = try await resolveReminder(arguments)
        let recordId = reminder.calendarItemIdentifier
        let title = reminder.title ?? "(无标题)"
        try store.remove(reminder, commit: true)
        return .object([
            "recordId": .string(recordId),
            "title": .string(title),
            "deleted": .bool(true),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ])
    }

    func updateCalendarEvent(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateCalendarPreview(arguments)
        let eventId = try arguments.requiredString("eventId")
        guard let event = store.event(withIdentifier: eventId) else {
            throw ToolExecutionError(code: "event_not_found", message: "没有找到这条日程，请先查询确认")
        }
        if let title = arguments.optionalString("title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event.title = title
        }
        if let rawStart = arguments.optionalString("startAt") {
            guard let start = ToolDate.parse(rawStart) else {
                throw ToolExecutionError(code: "invalid_time_range", message: "startAt 无法解析")
            }
            event.startDate = start
        }
        if let rawEnd = arguments.optionalString("endAt") {
            guard let end = ToolDate.parse(rawEnd) else {
                throw ToolExecutionError(code: "invalid_time_range", message: "endAt 无法解析")
            }
            event.endDate = end
        }
        guard event.endDate > event.startDate else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }
        if let location = arguments.optionalString("location") { event.location = location }
        if let notes = arguments.optionalString("notes") { event.notes = notes }
        if let calendarId = arguments.optionalString("calendarId"),
           let calendar = store.calendar(withIdentifier: calendarId) {
            event.calendar = calendar
        }
        try store.save(event, span: .thisEvent, commit: true)
        return .object([
            "eventId": .string(event.eventIdentifier ?? event.calendarItemIdentifier),
            "title": .string(event.title ?? "(无标题)"),
            "startAt": .string(ToolDate.iso(event.startDate)),
            "endAt": .string(ToolDate.iso(event.endDate)),
            "calendarId": .string(event.calendar?.calendarIdentifier ?? ""),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ])
    }

    func deleteCalendarEvent(arguments: [String: JSONValue]) throws -> JSONValue {
        let eventId = try arguments.requiredString("eventId")
        guard let event = store.event(withIdentifier: eventId) else {
            throw ToolExecutionError(code: "event_not_found", message: "没有找到这条日程，请先查询确认")
        }
        let title = event.title ?? "(无标题)"
        try store.remove(event, span: .thisEvent, commit: true)
        return .object([
            "eventId": .string(eventId),
            "title": .string(title),
            "deleted": .bool(true),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ])
    }

    private func fetchReminders(calendars: [EKCalendar]?) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func resolveReminder(_ arguments: [String: JSONValue]) async throws -> EKReminder {
        if let recordId = arguments.optionalString("recordId"), !recordId.isEmpty {
            guard let reminder = store.calendarItem(withIdentifier: recordId) as? EKReminder else {
                throw ToolExecutionError(code: "reminder_not_found", message: "没有找到这条提醒，请先查询确认")
            }
            return reminder
        }
        guard let title = arguments.optionalString("title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError(code: "missing_reminder_reference", message: "需要 recordId，或用于核对的提醒标题")
        }
        let dueAt = arguments.optionalString("dueAt").flatMap(ToolDate.parse)
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminders = await fetchReminders(calendars: nil)
        let matches = reminders.filter { reminder in
            guard (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return false }
            guard let dueAt else { return true }
            guard let due = reminder.dueDateComponents.flatMap({ ToolDate.calendar(TimeZone.current.identifier).date(from: $0) }) else { return false }
            return abs(due.timeIntervalSince(dueAt)) < 60
        }
        if matches.count > 1 {
            let timezone = TimeZone.current.identifier
            let candidates = matches.prefix(5).map { reminder -> String in
                let due = reminder.dueDateComponents
                    .flatMap { ToolDate.calendar(timezone).date(from: $0) }
                    .map { ToolDate.iso($0) } ?? "无截止时间"
                let list = reminder.calendar?.title ?? "提醒事项"
                return "\(due)｜\(list)｜\(reminder.calendarItemIdentifier)"
            }.joined(separator: "；")
            throw ToolExecutionError(
                code: "ambiguous_reminder",
                message: "找到 \(matches.count) 条同名提醒：\(candidates)。请补充具体日期/时间或 recordId 后再操作，不要直接修改第一条。"
            )
        }
        if let exact = matches.first { return exact }
        throw ToolExecutionError(code: "reminder_not_found", message: "没有找到匹配的提醒，请先查询确认，不要直接新建")
    }

    func reminderPresence(recordId: String) -> SystemRecordPresence {
        guard !recordId.isEmpty, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return .unobservable }
        return store.calendarItem(withIdentifier: recordId) is EKReminder ? .present : .missing
    }

    func calendarEventPresence(eventId: String) -> SystemRecordPresence {
        guard !eventId.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .unobservable }
        return store.event(withIdentifier: eventId) != nil ? .present : .missing
    }

    func calendarPreview(arguments: [String: JSONValue]) throws -> CalendarWritePreview {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ToolExecutionError(code: "calendar_read_required", message: "需要日历完整访问权限才能在写入前核对冲突。")
        }
        let existing = arguments.optionalString("eventId").flatMap { store.event(withIdentifier: $0) }
        if arguments.optionalString("eventId") != nil, existing == nil {
            throw ToolExecutionError(code: "event_not_found", message: "没有找到待修改的日程，请重新查询。")
        }
        let start = arguments.optionalString("startAt").flatMap(ToolDate.parse) ?? existing?.startDate
        let end = arguments.optionalString("endAt").flatMap(ToolDate.parse) ?? existing?.endDate
        guard let start, let end, end > start, end.timeIntervalSince(start) <= 366 * 86400 else {
            throw ToolExecutionError(code: "invalid_time_range", message: "请提供有效的起止时间；单条日程最长一年。")
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let conflicts = store.events(matching: predicate).filter {
            $0.eventIdentifier != existing?.eventIdentifier && $0.startDate < end && $0.endDate > start
        }.sorted { ($0.eventIdentifier ?? "") < ($1.eventIdentifier ?? "") }
        let title = arguments.optionalString("title") ?? existing?.title ?? "日程"
        var lines = ["\(title) · \(start.formatted(date: .abbreviated, time: .shortened)) → \(end.formatted(date: .abbreviated, time: .shortened))"]
        if let existing {
            lines.append("修改前：\(existing.title ?? "日程") · \(existing.startDate.formatted(date: .abbreviated, time: .shortened)) → \(existing.endDate.formatted(date: .abbreviated, time: .shortened))")
            if existing.hasRecurrenceRules { lines.append("重复日程：本次仅修改这一次，不修改后续系列。") }
        } else if arguments.optionalObject("recurrence") != nil {
            lines.append("重复日程：本次核对首次时段，后续重复仍可能存在冲突。")
        }
        lines.append(conflicts.isEmpty ? "未发现时间冲突" : "发现 \(conflicts.count) 个重叠日程：" + conflicts.prefix(5).map { $0.title ?? "日程" }.joined(separator: "、"))
        let fields = [title, ToolDate.iso(start), ToolDate.iso(end), existing?.title ?? "", existing.map { ToolDate.iso($0.startDate) } ?? "", existing.map { ToolDate.iso($0.endDate) } ?? ""] + conflicts.map { "\($0.eventIdentifier ?? "")|\($0.title ?? "")|\(ToolDate.iso($0.startDate))|\(ToolDate.iso($0.endDate))" }
        return CalendarWritePreview(detail: lines.joined(separator: "\n"), conflictCount: conflicts.count, fingerprint: CalendarWritePreview.hash(fields))
    }

    private func validateCalendarPreview(_ arguments: [String: JSONValue]) throws {
        let current = try calendarPreview(arguments: arguments)
        guard arguments.optionalString("_calendarPreviewFingerprint") == current.fingerprint else {
            throw ToolExecutionError(code: "calendar_preview_changed", message: "日历内容或冲突已变化，本次未写入；请重新核对确认。")
        }
    }

    private func reminderPayload(_ reminder: EKReminder, timezone: String) -> [String: JSONValue] {
        let due = reminder.dueDateComponents.flatMap { ToolDate.calendar(timezone).date(from: $0) }
        var row: [String: JSONValue] = [
            "recordId": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? "(无标题)"),
            "completed": .bool(reminder.isCompleted),
            "listName": .string(reminder.calendar?.title ?? "提醒事项"),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ]
        row["dueAt"] = due.map { JSONValue.string(ToolDate.iso($0)) } ?? .null
        if let notes = reminder.notes { row["notes"] = .string(notes) }
        return row
    }

    func listCalendarEvents(arguments: [String: JSONValue]) throws -> JSONValue {
        let start = try ToolDate.requiredDate(arguments, key: "startAt")
        let end = try ToolDate.requiredDate(arguments, key: "endAt")
        guard end > start else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }

        let calendarIds = arguments.optionalStringArray("calendarIds") ?? []
        let calendars: [EKCalendar]? = calendarIds.isEmpty
            ? nil
            : calendarIds.compactMap { store.calendar(withIdentifier: $0) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let payload: [JSONValue] = events.map { event in
            var row: [String: JSONValue] = [
                "eventId": .string(event.eventIdentifier ?? event.calendarItemIdentifier),
                "title": .string(event.title ?? "(无标题)"),
                "startAt": .string(ToolDate.iso(event.startDate)),
                "endAt": .string(ToolDate.iso(event.endDate)),
                "calendarId": .string(event.calendar?.calendarIdentifier ?? ""),
                "calendarTitle": .string(event.calendar?.title ?? ""),
                "location": event.location.map { JSONValue.string($0) } ?? .null,
                "isAllDay": .bool(event.isAllDay)
            ]
            if let notes = event.notes {
                row["notes"] = .string(notes)
            }
            return .object(row)
        }

        return .object([
            "events": .array(payload),
            "count": .number(Double(payload.count)),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ])
    }

    func findFreeSlots(arguments: [String: JSONValue]) throws -> JSONValue {
        let rangeStart = try ToolDate.requiredDate(arguments, key: "startAt")
        let rangeEnd = try ToolDate.requiredDate(arguments, key: "endAt")
        guard rangeEnd > rangeStart else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier
        let calendar = ToolDate.calendar(timezone)
        let duration = max(15, min(arguments.optionalInt("durationMinutes") ?? 60, 480))
        let buffer = max(0, min(arguments.optionalInt("bufferMinutes") ?? 0, 120))
        let limit = max(1, min(arguments.optionalInt("limit") ?? 8, 20))
        let includeAllDay = arguments.optionalBool("includeAllDay") ?? false
        let dayStart = parseClock(arguments.optionalString("dayStart") ?? "09:00", fallback: (9, 0))
        let dayEnd = parseClock(arguments.optionalString("dayEnd") ?? "21:00", fallback: (21, 0))
        guard dayStart.hour * 60 + dayStart.minute < dayEnd.hour * 60 + dayEnd.minute else {
            throw ToolExecutionError(code: "invalid_day_window", message: "dayStart 必须早于 dayEnd")
        }

        var slots: [JSONValue] = []
        var dayCursor = calendar.startOfDay(for: rangeStart)
        var inspectedDays = 0
        while dayCursor < rangeEnd, slots.count < limit, inspectedDays < 14 {
            if let windowStartOfDay = calendar.date(
                bySettingHour: dayStart.hour,
                minute: dayStart.minute,
                second: 0,
                of: dayCursor
            ), let windowEndOfDay = calendar.date(
                bySettingHour: dayEnd.hour,
                minute: dayEnd.minute,
                second: 0,
                of: dayCursor
            ) {
                let windowStart = max(windowStartOfDay, rangeStart)
                let windowEnd = min(windowEndOfDay, rangeEnd)
                if windowStart < windowEnd {
                    let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
                    let busy = store.events(matching: predicate)
                        .filter { includeAllDay || !$0.isAllDay }
                        .map { event in
                            (
                                start: max(windowStart, event.startDate.addingTimeInterval(-Double(buffer) * 60)),
                                end: min(windowEnd, event.endDate.addingTimeInterval(Double(buffer) * 60))
                            )
                        }
                        .filter { $0.start < $0.end }
                        .sorted { $0.start < $1.start }

                    var freeStart = windowStart
                    for interval in busy {
                        appendFreeSlots(
                            from: freeStart,
                            to: interval.start,
                            duration: duration,
                            timezone: timezone,
                            limit: limit,
                            into: &slots
                        )
                        if slots.count >= limit { break }
                        if interval.end > freeStart { freeStart = interval.end }
                        if freeStart >= windowEnd { break }
                    }
                    if slots.count < limit, freeStart < windowEnd {
                        appendFreeSlots(
                            from: freeStart,
                            to: windowEnd,
                            duration: duration,
                            timezone: timezone,
                            limit: limit,
                            into: &slots
                        )
                    }
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
            dayCursor = nextDay
            inspectedDays += 1
        }

        return .object([
            "slots": .array(slots),
            "count": .number(Double(slots.count)),
            "durationMinutes": .number(Double(duration)),
            "bufferMinutes": .number(Double(buffer)),
            "timezone": .string(timezone),
            "dayStart": .string(String(format: "%02d:%02d", dayStart.hour, dayStart.minute)),
            "dayEnd": .string(String(format: "%02d:%02d", dayEnd.hour, dayEnd.minute)),
            "source": .string("eventkit"),
            "simulated": .bool(false),
            "note": .string("空档按日历事件计算；创建前仍需你确认具体时段")
        ])
    }

    private func appendFreeSlots(
        from start: Date,
        to end: Date,
        duration: Int,
        timezone: String,
        limit: Int,
        into slots: inout [JSONValue]
    ) {
        let durationSeconds = Double(duration) * 60
        var cursor = start
        while cursor.addingTimeInterval(durationSeconds) <= end, slots.count < limit {
            let slotEnd = cursor.addingTimeInterval(durationSeconds)
            slots.append(.object([
                "startAt": .string(ToolDate.iso(cursor)),
                "endAt": .string(ToolDate.iso(slotEnd)),
                "durationMinutes": .number(Double(duration)),
                "timezone": .string(timezone)
            ]))
            cursor = slotEnd
        }
    }

    private func parseClock(_ raw: String, fallback: (hour: Int, minute: Int)) -> (hour: Int, minute: Int) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return fallback
        }
        return (hour, minute)
    }

    func createCalendarEvent(arguments: [String: JSONValue], operationId: String) throws -> JSONValue {
        try validateCalendarPreview(arguments)
        let title = try arguments.requiredString("title")
        let start = try ToolDate.requiredDate(arguments, key: "startAt")
        let end = try ToolDate.requiredDate(arguments, key: "endAt")
        guard end > start else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = arguments.optionalString("location")
        event.notes = arguments.optionalString("notes")
        if let recurrence = try recurrenceRule(from: arguments) {
            event.addRecurrenceRule(recurrence)
        }

        if let calendarId = arguments.optionalString("calendarId"), let calendar = store.calendar(withIdentifier: calendarId) {
            event.calendar = calendar
        } else if let defaultCalendar = store.defaultCalendarForNewEvents {
            event.calendar = defaultCalendar
        } else {
            throw ToolExecutionError(code: "calendar_missing", message: "没有可写的日历")
        }

        let conflicts = store.events(
            matching: store.predicateForEvents(withStart: start, end: end, calendars: event.calendar.map { [$0] })
        )

        try store.save(event, span: .thisEvent, commit: true)

        var row: [String: JSONValue] = [
            "eventId": .string(event.eventIdentifier ?? event.calendarItemIdentifier),
            "title": .string(title),
            "startAt": .string(ToolDate.iso(start)),
            "endAt": .string(ToolDate.iso(end)),
            "calendarId": .string(event.calendar?.calendarIdentifier ?? ""),
            "source": .string("eventkit"),
            "simulated": .bool(false)
        ]
        if let label = recurrenceLabel(from: arguments) {
            row["recurrence"] = .string(label)
        }
        row["operationId"] = .string(operationId)
        row["conflictCount"] = .number(Double(conflicts.count))
        if !conflicts.isEmpty {
            row["conflicts"] = .array(conflicts.prefix(5).map { conflict in
                .object([
                    "title": .string(conflict.title ?? "(无标题)"),
                    "startAt": .string(ToolDate.iso(conflict.startDate)),
                    "endAt": .string(ToolDate.iso(conflict.endDate))
                ])
            })
        }
        return .object(row)
    }

    private func existingReminderId(title: String, dueDate: Date?, calendar: EKCalendar) async -> String? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: [calendar]
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let match = (reminders ?? []).first { reminder in
                    let candidate = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard candidate == normalized else { return false }
                    switch (dueDate, reminder.dueDateComponents) {
                    case (nil, nil):
                        return true
                    case let (expected?, components?):
                        guard let existing = Calendar.current.date(from: components) else { return false }
                        return abs(existing.timeIntervalSince(expected)) < 60
                    default:
                        return false
                    }
                }
                continuation.resume(returning: match?.calendarItemIdentifier)
            }
        }
    }

    func findReminder(title: String, dueAt: Date?) async -> String? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let match = (reminders ?? []).first { reminder in
                    let candidate = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard candidate == normalized else { return false }
                    switch (dueAt, reminder.dueDateComponents) {
                    case (nil, nil):
                        return true
                    case let (expected?, components?):
                        guard let existing = Calendar.current.date(from: components) else { return false }
                        return abs(existing.timeIntervalSince(expected)) < 60
                    default:
                        return false
                    }
                }
                continuation.resume(returning: match?.calendarItemIdentifier)
            }
        }
    }

    func findCalendarEvent(title: String, startAt: Date) -> String? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let window: TimeInterval = 120
        let predicate = store.predicateForEvents(
            withStart: startAt.addingTimeInterval(-window),
            end: startAt.addingTimeInterval(window),
            calendars: nil
        )
        let match = store.events(matching: predicate).first { event in
            let candidate = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate == normalized && abs(event.startDate.timeIntervalSince(startAt)) < 60
        }
        return match?.eventIdentifier ?? match?.calendarItemIdentifier
    }

    private func resolveReminderCalendar(_ listId: String?) throws -> EKCalendar {
        store.refreshSourcesIfNecessary()
        if let listId, let calendar = store.calendar(withIdentifier: listId), calendar.allowsContentModifications {
            return calendar
        }
        if let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications {
            return calendar
        }
        if let calendar = store.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) {
            return calendar
        }
        return try createLocalReminderCalendar()
    }

    private func createLocalReminderCalendar() throws -> EKCalendar {
        store.refreshSourcesIfNecessary()
        let preferredTypes: [EKSourceType] = [.local, .mobileMe, .calDAV]
        var lastError: Error?
        let existingTitles = Set(store.calendars(for: .reminder).map(\.title))
        var title = "鲸鱼待办"
        var suffix = 2
        while existingTitles.contains(title) {
            title = "鲸鱼待办 \(suffix)"
            suffix += 1
        }

        for sourceType in preferredTypes {
            guard let source = store.sources.first(where: { $0.sourceType == sourceType }) else { continue }
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = title
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                return calendar
            } catch {
                lastError = error
            }
        }

        let detail = lastError?.localizedDescription ?? "系统没有可用的提醒事项账户"
        throw ToolExecutionError(
            code: "reminder_calendar_missing",
            message: "没有可写的提醒事项列表，自动创建也失败了：\(detail)。请打开系统「提醒事项」App 新建一个列表后再试。"
        )
    }

    private func recurrenceRule(from arguments: [String: JSONValue]) throws -> EKRecurrenceRule? {
        guard let raw = arguments["recurrence"], raw != .null else { return nil }
        guard let object = raw.objectValue else {
            throw ToolExecutionError(code: "invalid_recurrence", message: "recurrence 必须是对象")
        }
        guard let frequencyRaw = object.optionalString("frequency") else {
            throw ToolExecutionError(code: "invalid_recurrence", message: "recurrence.frequency 不能为空")
        }
        let frequency: EKRecurrenceFrequency
        switch frequencyRaw {
        case "daily": frequency = .daily
        case "weekly": frequency = .weekly
        case "monthly": frequency = .monthly
        case "yearly": frequency = .yearly
        default:
            throw ToolExecutionError(code: "invalid_recurrence", message: "不支持的重复频率 \(frequencyRaw)")
        }
        let interval = max(1, min(object.optionalInt("interval") ?? 1, 99))
        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        if frequency == .weekly, let values = object["weekdays"]?.arrayValue, !values.isEmpty {
            daysOfWeek = try values.map { item in
                guard let iso = item.intValue, (1...7).contains(iso) else {
                    throw ToolExecutionError(code: "invalid_recurrence", message: "weekdays 只能是 1（周一）到 7（周日）")
                }
                let rawWeekday = iso == 7 ? EKWeekday.sunday.rawValue : iso + 1
                guard let weekday = EKWeekday(rawValue: rawWeekday) else {
                    throw ToolExecutionError(code: "invalid_recurrence", message: "无法识别星期 \(iso)")
                }
                return EKRecurrenceDayOfWeek(dayOfTheWeek: weekday, weekNumber: 0)
            }
        }
        var end: EKRecurrenceEnd?
        if let rawUntil = object.optionalString("until") {
            guard let until = ToolDate.parse(rawUntil) else {
                throw ToolExecutionError(code: "invalid_recurrence", message: "recurrence.until 无法解析")
            }
            end = EKRecurrenceEnd(end: until)
        } else if let count = object.optionalInt("count") {
            end = EKRecurrenceEnd(occurrenceCount: max(1, min(count, 365)))
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private func recurrenceLabel(from arguments: [String: JSONValue]) -> String? {
        guard let object = arguments.optionalObject("recurrence"),
              let frequency = object.optionalString("frequency") else { return nil }
        let interval = max(1, min(object.optionalInt("interval") ?? 1, 99))
        let unit: String
        switch frequency {
        case "daily": unit = "天"
        case "weekly": unit = "周"
        case "monthly": unit = "月"
        case "yearly": unit = "年"
        default: return nil
        }
        var label = interval == 1 ? "每\(unit)" : "每 \(interval) \(unit)"
        if frequency == "weekly", let values = object["weekdays"]?.arrayValue {
            let names = ["一", "二", "三", "四", "五", "六", "日"]
            let days = values.compactMap { item -> String? in
                guard let iso = item.intValue, (1...7).contains(iso) else { return nil }
                return "周\(names[iso - 1])"
            }
            if !days.isEmpty { label += "（\(days.joined(separator: "、"))）" }
        }
        if let count = object.optionalInt("count") {
            label += "，共 \(max(1, min(count, 365))) 次"
        }
        if let until = object.optionalString("until") {
            label += "，至 \(until)"
        }
        return label
    }
}

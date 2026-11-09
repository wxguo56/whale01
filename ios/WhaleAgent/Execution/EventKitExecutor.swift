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

        guard let calendar = resolveReminderCalendar(arguments.optionalString("listId")) else {
            throw ToolExecutionError(code: "reminder_calendar_missing", message: "没有可写的提醒事项列表")
        }

        if let existingId = await existingReminderId(title: title, dueDate: dueDate, calendar: calendar) {
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
        row["operationId"] = .string(operationId)
        return .object(row)
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

    func createCalendarEvent(arguments: [String: JSONValue], operationId: String) throws -> JSONValue {
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

    private func resolveReminderCalendar(_ listId: String?) -> EKCalendar? {
        if let listId, let calendar = store.calendar(withIdentifier: listId), calendar.allowsContentModifications {
            return calendar
        }
        if let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications {
            return calendar
        }
        return store.calendars(for: .reminder).first { $0.allowsContentModifications }
    }
}

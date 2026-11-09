import Foundation

enum ToolDate {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    static func iso(_ date: Date) -> String {
        plainFormatter.string(from: date)
    }

    static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }

    static func calendar(_ timezone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone(timezone)
        return calendar
    }

    static func day(_ date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = zone(timezone)
        return formatter.string(from: date)
    }

    static func requiredDate(_ arguments: [String: JSONValue], key: String) throws -> Date {
        guard let raw = arguments.optionalString(key), let date = parse(raw) else {
            throw ToolExecutionError(code: "invalid_arguments", message: "\(key) 无法解析为 ISO 8601 时间")
        }
        return date
    }
}

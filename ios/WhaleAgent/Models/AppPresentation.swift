import CoreLocation
import Foundation
import SwiftUI

enum AppTab: Hashable {
    case conversation
    case records
    case settings
}

struct OperationRecord: Identifiable, Equatable, Codable {
    let id: String
    let tool: String
    let status: String
    let title: String
    let detail: String
    let createdAt: Date
    let source: String

    init(
        id: String,
        tool: String,
        status: String,
        title: String,
        detail: String,
        createdAt: Date = Date(),
        source: String = "chat"
    ) {
        self.id = id
        self.tool = tool
        self.status = status
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.source = source
    }

    var isSuccess: Bool { status == "success" }

    var icon: String {
        if !isSuccess { return "exclamationmark.triangle.fill" }
        switch tool {
        case "create_reminder": return "bell.badge.fill"
        case "list_reminders", "update_reminder", "delete_reminder": return "bell.badge"
        case "create_calendar_event", "list_calendar_events", "update_calendar_event", "delete_calendar_event":
            return "calendar"
        case "search_places", "open_navigation", "get_current_location": return "map.fill"
        case "prepare_message": return "message.fill"
        case "search_music_library", "play_music", "pause_music", "resume_music", "skip_music_track":
            return "music.note"
        case "get_weather": return "cloud.sun.fill"
        case "get_activity_summary": return "figure.walk"
        case "search_web", "fetch_web_content": return "safari.fill"
        case "search_merchant_prices": return "yensign.circle.fill"
        case "list_memory", "set_memory", "delete_memory": return "brain.head.profile"
        case "ocr_document": return "doc.viewfinder"
        default: return "sparkles"
        }
    }
}

struct PlaceSummary: Identifiable, Equatable, Codable {
    let placeId: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double

    var id: String { placeId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String {
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters.rounded())) 米"
        }
        return String(format: "%.1f 公里", distanceMeters / 1_000)
    }

    static func list(from data: JSONValue?) -> [PlaceSummary] {
        guard let rows = data?.objectValue?["places"]?.arrayValue else { return [] }
        return rows.compactMap { row in
            guard
                let object = row.objectValue,
                let placeId = object.optionalString("placeId"),
                let name = object.optionalString("name"),
                let latitude = object.optionalDouble("latitude"),
                let longitude = object.optionalDouble("longitude")
            else { return nil }
            return PlaceSummary(
                placeId: placeId,
                name: name,
                address: object.optionalString("address") ?? "",
                latitude: latitude,
                longitude: longitude,
                distanceMeters: object.optionalDouble("distanceMeters") ?? 0
            )
        }
    }

    static func current(from data: JSONValue?) -> [PlaceSummary] {
        guard
            let object = data?.objectValue,
            let latitude = object.optionalDouble("latitude"),
            let longitude = object.optionalDouble("longitude")
        else { return [] }

        let address = object.optionalString("displayAddress") ?? ""
        let name = object.optionalString("name")
            ?? (address.isEmpty ? "我的位置" : address)
        return [
            PlaceSummary(
                placeId: "current-location",
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                distanceMeters: 0
            )
        ]
    }
}

struct CalendarEventPreview: Identifiable, Equatable {
    let id: String
    let title: String
    let startAt: Date
    let endAt: Date
    let isAllDay: Bool
    let calendarTitle: String

    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        guard
            let id = object.optionalString("eventId"),
            let title = object.optionalString("title"),
            let startRaw = object.optionalString("startAt"),
            let start = ToolDate.parse(startRaw)
        else { return nil }
        let endRaw = object.optionalString("endAt")
        self.id = id
        self.title = title
        self.startAt = start
        self.endAt = endRaw.flatMap(ToolDate.parse) ?? start
        self.isAllDay = object["isAllDay"]?.boolValue ?? false
        self.calendarTitle = object.optionalString("calendarTitle") ?? "日历"
    }
}

struct WeatherDaySummary: Identifiable, Equatable, Codable {
    let date: String
    let condition: String
    let summary: String
    let minimumC: Double?
    let maximumC: Double?
    let precipitationChance: Double?
    let advice: String

    var id: String { date }

    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        let date = object.optionalString("date") ?? ""
        let summary = object.optionalString("summary") ?? ""
        guard !date.isEmpty, !summary.isEmpty else { return nil }
        let temperatures = object.optionalObject("temperatureC")
        self.date = date
        self.condition = object.optionalString("condition") ?? "unknown"
        self.summary = summary
        self.minimumC = temperatures?.optionalDouble("min")
        self.maximumC = temperatures?.optionalDouble("max")
        self.precipitationChance = object.optionalDouble("precipitationChance")
        self.advice = object.optionalString("advice") ?? ""
    }

    static func list(from data: JSONValue?) -> [WeatherDaySummary] {
        guard let object = data?.objectValue else { return [] }
        if let days = object["days"]?.arrayValue, !days.isEmpty {
            return days.compactMap { WeatherDaySummary(json: $0) }
        }
        return WeatherDaySummary(json: .object(object)).map { [$0] } ?? []
    }

    var temperatureText: String {
        switch (minimumC, maximumC) {
        case let (low?, high?):
            return "\(Self.degrees(low))° / \(Self.degrees(high))°"
        case let (nil, high?):
            return "最高 \(Self.degrees(high))°"
        case let (low?, nil):
            return "最低 \(Self.degrees(low))°"
        default:
            return "暂无温度"
        }
    }

    var precipitationText: String? {
        guard let precipitationChance else { return nil }
        return "降水 \(Int(precipitationChance.rounded()))%"
    }

    var dayLabel: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return date }
        let calendar = Calendar.current
        if calendar.isDateInToday(parsed) { return "今天" }
        if calendar.isDateInTomorrow(parsed) { return "明天" }
        return parsed.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    var icon: String {
        switch condition {
        case "clear": return "sun.max.fill"
        case "partlyCloudy": return "cloud.sun.fill"
        case "cloudy": return "cloud.fill"
        case "fog": return "cloud.fog.fill"
        case "drizzle", "rain": return "cloud.drizzle.fill"
        case "heavyRain", "showers": return "cloud.heavyrain.fill"
        case "snow": return "cloud.snow.fill"
        case "thunderstorm": return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    private static func degrees(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

struct MusicTrackItem: Identifiable, Equatable {
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let durationSec: Double
    let artworkURL: URL?
    let source: String

    var id: String { trackId }

    var isLocal: Bool { source == "local" }

    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        guard let trackId = object.optionalString("trackId"), let title = object.optionalString("title") else {
            return nil
        }
        self.trackId = trackId
        self.title = title
        self.artist = object.optionalString("artist") ?? "未知艺人"
        self.album = object.optionalString("album") ?? ""
        self.durationSec = object.optionalDouble("durationSec") ?? 0
        self.artworkURL = object.optionalString("artworkURL").flatMap(URL.init(string:))
        self.source = object.optionalString("source") ?? "musickit"
    }

    var durationText: String {
        guard durationSec > 0 else { return "" }
        let seconds = Int(durationSec.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct PlaybackSnapshot: Equatable {
    let state: String
    let track: MusicTrackItem?
    let positionSec: Double
    let queueLength: Int
    let audioOutput: Bool

    static let idle = PlaybackSnapshot(
        state: "stopped",
        track: nil,
        positionSec: 0,
        queueLength: 0,
        audioOutput: false
    )

    init(json: JSONValue?) {
        guard let object = json?.objectValue else {
            self = .idle
            return
        }
        state = object.optionalString("state") ?? "stopped"
        track = object["track"].flatMap(MusicTrackItem.init(json:))
        positionSec = object.optionalDouble("positionSec") ?? 0
        queueLength = object.optionalInt("queueLength") ?? 0
        audioOutput = object["audioOutput"]?.boolValue ?? false
    }

    private init(state: String, track: MusicTrackItem?, positionSec: Double, queueLength: Int, audioOutput: Bool) {
        self.state = state
        self.track = track
        self.positionSec = positionSec
        self.queueLength = queueLength
        self.audioOutput = audioOutput
    }

    var isPlaying: Bool { state == "playing" }
    var stateText: String {
        switch state {
        case "playing": return "正在播放"
        case "paused": return "已暂停"
        default: return "未播放"
        }
    }
}

enum ToolPresentation {
    static func title(_ tool: String) -> String {
        ToolCatalog.label(tool)
    }

    static func icon(_ tool: String) -> String {
        switch tool {
        case "create_reminder": return "bell.badge"
        case "list_reminders", "update_reminder", "delete_reminder": return "bell.badge"
        case "list_calendar_events", "find_free_slots", "create_calendar_event", "update_calendar_event", "delete_calendar_event":
            return "calendar"
        case "get_weather": return "cloud.sun"
        case "get_activity_summary": return "figure.walk"
        case "search_places": return "mappin.and.ellipse"
        case "get_current_location": return "location.fill"
        case "open_navigation": return "location.north.line"
        case "prepare_message": return "message"
        case "search_music_library": return "music.note.list"
        case "play_music", "pause_music", "resume_music", "skip_music_track", "get_playback_state":
            return "music.note"
        case "summarize_shared_content": return "doc.text"
        case "list_memory", "set_memory", "delete_memory": return "brain.head.profile"
        case "search_web", "fetch_web_content": return "safari"
        case "search_merchant_prices": return "yensign.circle"
        default: return "sparkles"
        }
    }

    static func detail(for pending: PendingTool) -> String {
        let args = pending.arguments
        switch pending.tool {
        case "create_reminder":
            return join(
                args.optionalString("title"),
                formatDateTime(args.optionalString("dueAt")),
                recurrenceText(args.optionalObject("recurrence"))
            )
        case "list_reminders":
            if let start = args.optionalString("startAt"), let end = args.optionalString("endAt") {
                return formatDateRange(start: start, end: end)
            }
            return "查询系统提醒事项"
        case "update_reminder":
            return join(
                args.optionalString("newTitle") ?? args.optionalString("title") ?? args.optionalString("recordId"),
                formatDateTime(args.optionalString("dueAt")),
                args.optionalBool("completed") == true ? "标记完成" : nil
            )
        case "delete_reminder":
            return join(args.optionalString("title") ?? args.optionalString("recordId"), "删除系统提醒")
        case "create_calendar_event":
            return join(
                args.optionalString("title"),
                formatDateRange(start: args.optionalString("startAt"), end: args.optionalString("endAt")),
                recurrenceText(args.optionalObject("recurrence"))
            )
        case "update_calendar_event":
            return join(args.optionalString("title") ?? args.optionalString("eventId"), "修改系统日程")
        case "delete_calendar_event":
            return join(args.optionalString("title") ?? args.optionalString("eventId"), "删除系统日程")
        case "list_calendar_events":
            return formatDateRange(start: args.optionalString("startAt"), end: args.optionalString("endAt"))
        case "find_free_slots":
            return join(
                formatDateRange(start: args.optionalString("startAt"), end: args.optionalString("endAt")),
                args.optionalInt("durationMinutes").map { "\($0) 分钟" },
                "查找空闲时段"
            )
        case "search_places":
            return args.optionalString("query") ?? "搜索附近地点"
        case "get_current_location":
            return "读取手机当前位置"
        case "open_navigation":
            return "交给系统地图继续导航"
        case "prepare_message":
            let channel = args.optionalString("channel") == "email" ? "邮件" : "短信"
            return join(channel, args.optionalString("recipientId"), args.optionalString("body"))
        case "search_music_library":
            return args.optionalString("query") ?? "读取你的音乐库"
        case "play_music":
            return "播放你选择的曲目"
        case "skip_music_track":
            return args.optionalString("direction") == "previous" ? "回到上一首" : "播放下一首"
        case "get_weather":
            return join(args.optionalString("locationName"), formatDate(args.optionalString("startAt")))
        case "get_activity_summary":
            return "读取今天的步数、活动能量与锻炼时间"
        case "set_memory":
            return join(args.optionalString("key"), args.optionalString("value"))
        case "delete_memory":
            return args.optionalString("key") ?? "删除一条偏好"
        case "search_web":
            return args.optionalString("query") ?? "搜索网页来源"
        case "fetch_web_content":
            return args.optionalString("url") ?? "读取网页正文"
        case "search_merchant_prices":
            return [args.optionalString("merchant"), args.optionalString("branch"), args.optionalString("city")]
                .compactMap { $0 }
                .joined(separator: " · ")
        default:
            return ToolCatalog.summary(pending)
        }
    }

    static func confirmationNote(_ tool: String) -> String {
        switch tool {
        case "create_reminder":
            return "确认后会立即写入系统“提醒事项”，并设置到点提醒。"
        case "update_reminder":
            return "确认后会修改系统里的同一条提醒；不会另建一条。"
        case "delete_reminder":
            return "确认后会从系统“提醒事项”删除这条记录。"
        case "update_calendar_event":
            return "确认后会修改系统日历中的同一条日程。"
        case "delete_calendar_event":
            return "确认后会从系统日历删除这条日程。"
        case "create_calendar_event":
            return "确认后会立即写入系统日历，不会先创建模拟事件。"
        case "open_navigation":
            return "确认后会把地点交给系统地图；鲸鱼不会声称已经开始导航。"
        case "prepare_message":
            return "确认后只会打开系统短信草稿，是否发送由你在系统中决定。"
        default:
            return "确认后会在你的 iPhone 上执行这项系统操作。"
        }
    }

    static func resultDetail(tool: String, status: String, data: JSONValue?, error: ToolErrorPayload?) -> String {
        if let error { return error.message }
        guard let object = data?.objectValue else { return status == "success" ? "已完成" : status }

        switch tool {
        case "list_calendar_events":
            let count = object.optionalInt("count") ?? 0
            return count == 0 ? "已读取系统日历 · 这段时间没有安排" : "已读取系统日历 · \(count) 项"
        case "find_free_slots":
            let count = object.optionalInt("count") ?? 0
            return count == 0 ? "没有找到符合条件的空档" : "找到 \(count) 个候选空档 · 创建前仍需确认"
        case "list_reminders":
            let count = object.optionalInt("count") ?? 0
            return count == 0 ? "已读取系统提醒 · 当前没有匹配项" : "已读取系统提醒 · \(count) 项"
        case "update_reminder":
            let time = formatDateTime(object.optionalString("dueAt")).map { " · \($0)" } ?? ""
            let completed = object.optionalBool("completed") == true ? " · 已完成" : ""
            return "已修改系统提醒\(time)\(completed)"
        case "delete_reminder":
            return "已从系统提醒事项删除"
        case "update_calendar_event":
            let time = formatDateTime(object.optionalString("startAt")).map { " · \($0)" } ?? ""
            return "已修改系统日程\(time)"
        case "delete_calendar_event":
            return "已从系统日历删除"
        case "search_places":
            let count = object.optionalInt("count") ?? 0
            return count == 0 ? "没有找到候选地点 · 未打开地图" : "找到 \(count) 个候选地点 · 未打开地图"
        case "open_navigation":
            return object.optionalString("note") ?? "已交给系统地图"
        case "create_reminder":
            let time = formatDateTime(object.optionalString("dueAt")).map { " · \($0)" } ?? ""
            if object.optionalBool("deduplicated") == true {
                return "已存在相同提醒，未重复创建\(time)"
            }
            let repeatText = object.optionalString("recurrence").map { " · \($0)" } ?? ""
            return "已写入提醒事项\(time)\(repeatText)"
        case "create_calendar_event":
            let time = formatDateTime(object.optionalString("startAt")).map { " · \($0)" } ?? ""
            let conflicts = object.optionalInt("conflictCount") ?? 0
            let repeatText = object.optionalString("recurrence").map { " · \($0)" } ?? ""
            return conflicts > 0 ? "已写入系统日历\(time)\(repeatText) · 与 \(conflicts) 个日程重叠" : "已写入系统日历\(time)\(repeatText)"
        case "set_memory":
            return "已保存偏好 · 可随时修改或删除"
        case "delete_memory":
            return object.optionalBool("deleted") == true ? "已删除该偏好" : "没有找到这条偏好"
        case "search_web":
            let count = object.optionalInt("count") ?? 0
            return count == 0 ? "没有找到网页来源" : "找到 \(count) 个网页来源 · 需再读正文"
        case "fetch_web_content":
            let title = object.optionalString("title") ?? "网页"
            let chars = object.optionalInt("charCount") ?? 0
            return "已读取「\(title)」· \(chars) 字"
        case "search_merchant_prices":
            let count = object.optionalInt("evidenceCount") ?? 0
            return count == 0 ? "没有提取到可核对价格 · 未编造" : "找到 \(count) 条公开价格线索 · 未与商家核实"
        case "get_current_location":
            if object.optionalBool("addressResolved") == true {
                let address = object.optionalString("displayAddress") ?? "当前位置"
                let accuracy = object.optionalInt("accuracyMeters") ?? 0
                return "\(address) · 精度约 \(accuracy) 米"
            }
            let accuracy = object.optionalInt("accuracyMeters") ?? 0
            return "已取得坐标 · 精度约 \(accuracy) 米 · 地址未解析"
        default:
            break
        }

        switch object.optionalString("source") {
        case "messageui":
            return object.optionalString("note") ?? "已打开系统草稿"
        case "musickit":
            return object.optionalString("note") ?? "已读取系统音乐库"
        default:
            return data?.displayText ?? "已完成"
        }
    }

    static func formatDate(_ raw: String?) -> String? {
        guard let raw, let date = ToolDate.parse(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func formatDateTime(_ raw: String?) -> String? {
        guard let raw, let date = ToolDate.parse(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func formatDateRange(start: String?, end: String?) -> String {
        guard let startDate = start.flatMap(ToolDate.parse) else { return "安排日程" }
        let endDate = end.flatMap(ToolDate.parse)
        let startText = formatDateTime(start)
            ?? "\(formatShortDate(startDate)) \(formatTime(startDate))"
        guard let endDate else { return startText }
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return "\(startText)–\(formatTime(endDate))"
        }
        return "\(startText) 至 \(formatDateTime(end))"
    }

    private static func join(_ values: String?...) -> String {
        values.compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private static func recurrenceText(_ object: [String: JSONValue]?) -> String? {
        guard let object, let frequency = object.optionalString("frequency") else { return nil }
        let interval = max(1, object.optionalInt("interval") ?? 1)
        let unit: String
        switch frequency {
        case "daily": unit = "天"
        case "weekly": unit = "周"
        case "monthly": unit = "月"
        case "yearly": unit = "年"
        default: return nil
        }
        var text = interval == 1 ? "每\(unit)" : "每 \(interval) \(unit)"
        if frequency == "weekly", let values = object["weekdays"]?.arrayValue {
            let names = ["一", "二", "三", "四", "五", "六", "日"]
            let days = values.compactMap { item -> String? in
                guard let iso = item.intValue, (1...7).contains(iso) else { return nil }
                return "周\(names[iso - 1])"
            }
            if !days.isEmpty { text += "（\(days.joined(separator: "、"))）" }
        }
        return text
    }
}

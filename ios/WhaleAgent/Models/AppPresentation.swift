import Foundation
import SwiftUI

enum AppTab: Hashable {
    case home
    case chat
    case music
    case settings
}

struct NativeActionRecord: Identifiable, Equatable {
    let id = UUID()
    let tool: String
    let status: String
    let title: String
    let detail: String
    let createdAt = Date()

    var isSuccess: Bool { status == "success" }

    var icon: String {
        if !isSuccess { return "exclamationmark.triangle.fill" }
        switch tool {
        case "create_reminder": return "bell.badge.fill"
        case "create_calendar_event", "list_calendar_events": return "calendar"
        case "search_places", "open_navigation": return "map.fill"
        case "prepare_message": return "message.fill"
        case "search_music_library", "play_music", "pause_music", "resume_music", "skip_music_track":
            return "music.note"
        case "get_weather": return "cloud.sun.fill"
        case "get_activity_summary": return "figure.walk"
        default: return "sparkles"
        }
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

struct MusicTrackItem: Identifiable, Equatable {
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let durationSec: Double
    let artworkURL: URL?

    var id: String { trackId }

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
        case "list_calendar_events", "create_calendar_event": return "calendar"
        case "get_weather": return "cloud.sun"
        case "get_activity_summary": return "figure.walk"
        case "search_places": return "mappin.and.ellipse"
        case "open_navigation": return "location.north.line"
        case "prepare_message": return "message"
        case "search_music_library": return "music.note.list"
        case "play_music", "pause_music", "resume_music", "skip_music_track", "get_playback_state":
            return "music.note"
        case "summarize_shared_content": return "doc.text"
        default: return "sparkles"
        }
    }

    static func detail(for pending: PendingTool) -> String {
        let args = pending.arguments
        switch pending.tool {
        case "create_reminder":
            return join(
                args.optionalString("title"),
                formatDateTime(args.optionalString("dueAt"))
            )
        case "create_calendar_event":
            return join(
                args.optionalString("title"),
                formatDateRange(start: args.optionalString("startAt"), end: args.optionalString("endAt"))
            )
        case "list_calendar_events":
            return formatDateRange(start: args.optionalString("startAt"), end: args.optionalString("endAt"))
        case "search_places":
            return args.optionalString("query") ?? "搜索附近地点"
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
        default:
            return ToolCatalog.summary(pending)
        }
    }

    static func confirmationNote(_ tool: String) -> String {
        switch tool {
        case "create_reminder":
            return "确认后会立即写入系统“提醒事项”，并设置到点提醒。"
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
            return "已写入提醒事项\(time)"
        case "create_calendar_event":
            let time = formatDateTime(object.optionalString("startAt")).map { " · \($0)" } ?? ""
            let conflicts = object.optionalInt("conflictCount") ?? 0
            return conflicts > 0 ? "已写入系统日历\(time) · 与 \(conflicts) 个日程重叠" : "已写入系统日历\(time)"
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
}

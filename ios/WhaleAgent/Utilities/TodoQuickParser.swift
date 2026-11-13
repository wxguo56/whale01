import Foundation

enum TodoQuickParser {
    struct Added {
        let title: String
        let dueAt: Date?
        var validationError: String? = nil
    }

    private struct DayMatch {
        let date: Date
        let tokens: [String]
        let isWeekday: Bool
        let defaultHour: Int?
        let defaultMinute: Int?
    }

    private struct TimeMatch {
        let hour: Int
        let minute: Int
        let tokens: [String]
    }

    static func parseAdd(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Added {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "^(修改|改成|改为|推迟|提前|取消|不要|别)|^把.+(改|推迟|提前)|每(天|周|月|年)", options: .regularExpression) != nil {
            return Added(title: text, dueAt: nil, validationError: "这句话涉及修改、取消或重复提醒，请到对话里说明目标；这里没有新增待办。")
        }
        let prefixActions = ["提醒我", "帮我记一下", "帮我记着", "记一下", "新增待办", "新建待办", "待办", "todo:", "todo："]
        for prefix in prefixActions where text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。. "))
        guard !text.isEmpty else { return Added(title: "", dueAt: nil, validationError: "请写具体的待办内容。") }
        if let regex = try? NSRegularExpression(pattern: "([0-9]+)\\s*(分钟|小时)后"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let amountRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text),
           let tokenRange = Range(match.range, in: text),
           let amount = Double(text[amountRange]), amount > 0, amount <= 10080 {
            let seconds = amount * (text[unitRange] == "小时" ? 3600 : 60)
            let title = text.replacingCharacters(in: tokenRange, with: "").replacingOccurrences(of: "提醒我", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Added(title: title, dueAt: now.addingTimeInterval(seconds))
        }

        if let day = resolveDay(in: text, now: now, calendar: calendar),
           let time = resolveTime(in: text) {
            var components = calendar.dateComponents([.year, .month, .day], from: day.date)
            components.hour = time.hour
            components.minute = time.minute
            components.second = 0
            if var date = calendar.date(from: components) {
                if date <= now, day.isWeekday {
                    date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
                }
                if date > now {
                    var title = text
                    for token in day.tokens + time.tokens + ["提醒我"] {
                        title = title.replacingOccurrences(of: token, with: " ")
                    }
                    title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.:："))
                    return Added(title: title.isEmpty ? text : title, dueAt: date)
                }
            }
        }

        if resolveDay(in: text, now: now, calendar: calendar) != nil || resolveTime(in: text) != nil || text.range(of: "(后|前|[点时]|[:：][0-9]|下周|下个月|月底|周末|早上|晚上|下午|中午|今晚|明早|明晚|[0-9]+月[0-9]+[日号])", options: .regularExpression) != nil {
            return Added(title: text, dueAt: nil, validationError: "提醒时间不完整、已过去或暂时无法解析。请写清日期和时间，例如“明天下午三点取快递”；草稿已保留。")
        }
        let cleaned = text.replacingOccurrences(of: "提醒我", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Added(title: cleaned.isEmpty ? text : cleaned, dueAt: nil)
    }

    private static func resolveDay(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        let start = calendar.startOfDay(for: now)
        let relative: [(String, Int)] = [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0)]
        for (token, offset) in relative where text.contains(token) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            return DayMatch(date: date, tokens: [token], isWeekday: false, defaultHour: nil, defaultMinute: nil)
        }

        if text.contains("今晚") {
            return DayMatch(date: start, tokens: ["今晚"], isWeekday: false, defaultHour: 20, defaultMinute: 0)
        }
        if text.contains("明早") {
            guard let date = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DayMatch(date: date, tokens: ["明早"], isWeekday: false, defaultHour: 8, defaultMinute: 0)
        }
        if text.contains("明晚") {
            guard let date = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DayMatch(date: date, tokens: ["明晚"], isWeekday: false, defaultHour: 20, defaultMinute: 0)
        }

        let weekdays: [(String, Int)] = [
            ("一", 2), ("二", 3), ("三", 4), ("四", 5),
            ("五", 6), ("六", 7), ("日", 1), ("天", 1)
        ]
        for (character, weekday) in weekdays {
            for prefix in ["下周", "周", "星期", "礼拜"] {
                let token = prefix + character
                guard text.contains(token) else { continue }
                let current = calendar.component(.weekday, from: now)
                var delta = (weekday - current + 7) % 7
                if prefix == "下周" { delta = 7 - ((current + 5) % 7) + ((weekday + 5) % 7) }
                guard let date = calendar.date(byAdding: .day, value: delta, to: start) else { continue }
                return DayMatch(date: date, tokens: [token], isWeekday: true, defaultHour: nil, defaultMinute: nil)
            }
        }
        return nil
    }

    private static func resolveTime(in text: String) -> TimeMatch? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let regex = try? NSRegularExpression(pattern: "(上午|早上|中午|下午|傍晚|晚上|夜里)?\\s*([0-9]{1,2})\\s*[:：]\\s*([0-9]{2})"),
           let match = regex.firstMatch(in: text, range: fullRange) {
            let period = match.range(at: 1).location == NSNotFound ? (text.contains("今晚") || text.contains("明晚") ? "晚上" : "") : nsText.substring(with: match.range(at: 1))
            var hour = Int(nsText.substring(with: match.range(at: 2))) ?? -1
            let minute = Int(nsText.substring(with: match.range(at: 3))) ?? -1
            adjustPeriod(&hour, period: period)
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return TimeMatch(hour: hour, minute: minute, tokens: [nsText.substring(with: match.range)])
        }

        let pattern = "(上午|早上|中午|下午|傍晚|晚上|夜里)?\\s*([0-9]{1,2}|[一二三四五六七八九十]{1,3})\\s*[点时](半|[0-9]{1,2}\\s*分)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange) else { return nil }

        let period = match.range(at: 1).location == NSNotFound ? (text.contains("今晚") || text.contains("明晚") ? "晚上" : "") : nsText.substring(with: match.range(at: 1))
        let hourText = nsText.substring(with: match.range(at: 2))
        guard var hour = chineseNumber(hourText) else { return nil }
        var minute = 0
        if match.range(at: 3).location != NSNotFound {
            let minuteText = nsText.substring(with: match.range(at: 3)).replacingOccurrences(of: "分", with: "").trimmingCharacters(in: .whitespaces)
            minute = minuteText == "半" ? 30 : (Int(minuteText) ?? 0)
        }
        adjustPeriod(&hour, period: period)
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeMatch(hour: hour, minute: minute, tokens: [nsText.substring(with: match.range)])
    }

    private static func adjustPeriod(_ hour: inout Int, period: String) {
        switch period {
        case "下午", "傍晚", "晚上", "夜里":
            if hour < 12 { hour += 12 }
        case "中午":
            if hour < 11 { hour += 12 }
        default:
            break
        }
    }

    private static func chineseNumber(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let map: [Character: Int] = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        let characters = Array(text)
        if characters.count == 1 { return map[characters[0]] }
        if characters.count == 2 {
            if characters[0] == "十" { return 10 + (map[characters[1]] ?? 0) }
            if characters[1] == "十" { return (map[characters[0]] ?? 0) * 10 }
        }
        return nil
    }
}


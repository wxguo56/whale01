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
        for prefix in ["请", "帮我", "我想", "我要"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        let explicitAdd = ["新增待办", "新建待办", "待办", "todo:", "todo："].contains { text.lowercased().hasPrefix($0) }
        if !explicitAdd, text.range(of: "^(修改|改成|改为|推迟|提前|取消|不要|别|先别|不用|不需要|删除|删掉|移除|标记完成|恢复)|把.+(改|推迟|提前|删除|删掉|移除|完成|恢复|取消)|每(天|周|月|年)", options: .regularExpression) != nil {
            return Added(title: text, dueAt: nil, validationError: "这句话涉及修改、取消或重复提醒，请到对话里说明目标；这里没有新增待办。")
        }
        let prefixActions = ["提醒我", "帮我记一下", "帮我记着", "记一下", "新增待办", "新建待办", "待办", "todo:", "todo："]
        for prefix in prefixActions where text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。. "))
        guard !text.isEmpty else { return Added(title: "", dueAt: nil, validationError: "请写具体的待办内容。") }
        if let regex = try? NSRegularExpression(pattern: "(?<![0-9.])([0-9]+(?:\\.[0-9]+)?|半)\\s*个?\\s*(分钟|小时)后"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let amountRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text),
           let tokenRange = Range(match.range, in: text),
           let amount = text[amountRange] == "半" ? 0.5 : Double(text[amountRange]), amount > 0, amount <= 10080 {
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

        let temporalMarker = #"([0-9一二三四五六七八九十两半几]+\s*个?\s*(分钟|小时|天|周)(后|前)|[0-9一二三四五六七八九十两]+\s*[点时]|[:：][0-9]|下周|下个月|月底|周末|早上|晚上|下午|中午|今晚|明早|明晚|稍后|待会|等会|[0-9]+月[0-9]+[日号])"#
        if resolveDay(in: text, now: now, calendar: calendar) != nil || resolveTime(in: text) != nil || text.range(of: temporalMarker, options: .regularExpression) != nil {
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
            for prefix in ["下周", "下星期", "下礼拜", "周", "星期", "礼拜"] {
                let token = prefix + character
                guard text.contains(token) else { continue }
                let current = calendar.component(.weekday, from: now)
                var delta = (weekday - current + 7) % 7
                if prefix.hasPrefix("下") { delta = 7 - ((current + 5) % 7) + ((weekday + 5) % 7) }
                guard let date = calendar.date(byAdding: .day, value: delta, to: start) else { continue }
                return DayMatch(date: date, tokens: [token], isWeekday: true, defaultHour: nil, defaultMinute: nil)
            }
        }
        return nil
    }

    private static func resolveTime(in text: String) -> TimeMatch? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let regex = try? NSRegularExpression(pattern: "(凌晨|上午|早上|中午|下午|傍晚|晚上|夜里)?\\s*(?<![0-9])([0-9]{1,2})\\s*[:：]\\s*([0-9]{2})"),
           let match = regex.firstMatch(in: text, range: fullRange) {
            let period = match.range(at: 1).location == NSNotFound ? inferredPeriod(text) : nsText.substring(with: match.range(at: 1))
            var hour = Int(nsText.substring(with: match.range(at: 2))) ?? -1
            let minute = Int(nsText.substring(with: match.range(at: 3))) ?? -1
            guard periodIsConsistent(period, hour: hour) else { return nil }
            adjustPeriod(&hour, period: period)
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return TimeMatch(hour: hour, minute: minute, tokens: [nsText.substring(with: match.range)])
        }

        let pattern = "(凌晨|上午|早上|中午|下午|傍晚|晚上|夜里)?\\s*(?<![0-9零一二两三四五六七八九十])([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})\\s*[点时](半|[0-9零一二两三四五六七八九十]{1,3}\\s*分|[一二三123]\\s*刻)?整?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange) else { return nil }

        let period = match.range(at: 1).location == NSNotFound ? inferredPeriod(text) : nsText.substring(with: match.range(at: 1))
        let hourText = nsText.substring(with: match.range(at: 2))
        guard var hour = chineseNumber(hourText) else { return nil }
        guard !period.isEmpty || !(1...12).contains(hour) else { return nil }
        guard periodIsConsistent(period, hour: hour) else { return nil }
        var minute = 0
        if match.range(at: 3).location != NSNotFound {
            let suffix = nsText.substring(with: match.range(at: 3)).replacingOccurrences(of: " ", with: "")
            if suffix == "半" { minute = 30 }
            else if suffix.hasSuffix("刻"), let value = chineseNumber(String(suffix.dropLast())) { minute = value * 15 }
            else if suffix.hasSuffix("分"), let value = chineseNumber(String(suffix.dropLast())) { minute = value }
            else { return nil }
        }
        let tail = nsText.substring(from: match.range.location + match.range.length)
        if ["多", "左右", "刚过"].contains(where: tail.hasPrefix) { return nil }
        adjustPeriod(&hour, period: period)
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeMatch(hour: hour, minute: minute, tokens: [nsText.substring(with: match.range)])
    }

    private static func inferredPeriod(_ text: String) -> String {
        if text.contains("明早") || text.contains("今早") { return "早上" }
        if text.contains("今晚") || text.contains("明晚") { return "晚上" }
        return ""
    }

    private static func periodIsConsistent(_ period: String, hour: Int) -> Bool {
        if ["凌晨", "上午", "早上"].contains(period), hour > 12 { return false }
        if ["晚上", "夜里"].contains(period), (0...5).contains(hour) || hour == 12 { return false }
        if ["下午", "傍晚", "中午"].contains(period), hour == 0 { return false }
        return true
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
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        let characters = Array(text)
        if characters.count == 1 { return map[characters[0]] }
        if characters.count == 2 {
            if characters[0] == "十", let unit = map[characters[1]], unit < 10 { return 10 + unit }
            if characters[1] == "十", let tens = map[characters[0]], (1...9).contains(tens) { return tens * 10 }
            if let first = map[characters[0]], let second = map[characters[1]], first < 10, second < 10 { return first * 10 + second }
        }
        if characters.count == 3, characters[1] == "十", let tens = map[characters[0]], let unit = map[characters[2]], (1...9).contains(tens), unit < 10 { return tens * 10 + unit }
        return nil
    }
}


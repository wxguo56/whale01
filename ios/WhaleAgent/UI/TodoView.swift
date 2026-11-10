import SwiftUI
import UIKit

struct TodoReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let completed: Bool
    let listName: String
    let dueAt: Date?
    let notes: String?

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let id = object.optionalString("recordId"),
              let title = object.optionalString("title"),
              !title.isEmpty else { return nil }
        self.id = id
        self.title = title
        self.completed = object.optionalBool("completed") ?? false
        self.listName = object.optionalString("listName") ?? "提醒事项"
        self.dueAt = object.optionalString("dueAt").flatMap(ToolDate.parse)
        self.notes = object.optionalString("notes")
    }
}

private enum TodoFilter: String, CaseIterable, Identifiable {
    case pending
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待办"
        case .completed: return "已完成"
        }
    }
}

private enum TodoQuickCommand {
    case complete(String)
    case restore(String)
    case delete(String)

    static func parse(_ raw: String) -> TodoQuickCommand? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let actions: [(String, (String) -> TodoQuickCommand)] = [
            ("标记完成", TodoQuickCommand.complete),
            ("取消完成", TodoQuickCommand.restore),
            ("已完成", TodoQuickCommand.complete),
            ("完成", TodoQuickCommand.complete),
            ("勾掉", TodoQuickCommand.complete),
            ("恢复", TodoQuickCommand.restore),
            ("删除", TodoQuickCommand.delete),
            ("删掉", TodoQuickCommand.delete),
            ("移除", TodoQuickCommand.delete)
        ]

        for (prefix, make) in actions where text.hasPrefix(prefix) {
            var rest = String(text.dropFirst(prefix.count))
            guard let first = rest.first, first.isWhitespace || first == "：" || first == ":" || first == "，" || first == "," else {
                continue
            }
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return make(rest) }
        }

        for suffix in ["完成了", "做完了", "已完成", "搞定了"] where text.hasSuffix(suffix) {
            let rest = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return .complete(rest) }
        }

        return nil
    }
}

private enum TodoQuickParser {
    struct Added {
        let title: String
        let dueAt: Date?
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
        let prefixActions = ["提醒我", "帮我记一下", "帮我记着", "记一下", "新增待办", "新建待办", "待办", "todo:", "todo："]
        for prefix in prefixActions where text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。. "))
        guard !text.isEmpty else { return Added(title: raw, dueAt: nil) }

        if let day = resolveDay(in: text, now: now, calendar: calendar),
           let time = resolveTime(in: text) ?? day.defaultHour.map({ TimeMatch(hour: $0, minute: day.defaultMinute ?? 0, tokens: []) }) {
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
                if prefix == "下周" { delta += 7 }
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
            let period = match.range(at: 1).location == NSNotFound ? "" : nsText.substring(with: match.range(at: 1))
            var hour = Int(nsText.substring(with: match.range(at: 2))) ?? -1
            let minute = Int(nsText.substring(with: match.range(at: 3))) ?? -1
            adjustPeriod(&hour, period: period)
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return TimeMatch(hour: hour, minute: minute, tokens: [nsText.substring(with: match.range)])
        }

        let pattern = "(上午|早上|中午|下午|傍晚|晚上|夜里)?\\s*([0-9]{1,2}|[一二三四五六七八九十]{1,3})\\s*[点时](半|[0-9]{1,2}\\s*分)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange) else { return nil }

        let period = match.range(at: 1).location == NSNotFound ? "" : nsText.substring(with: match.range(at: 1))
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

struct TodoView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceInputController()

    @State private var filter: TodoFilter = .pending
    @State private var items: [TodoReminder] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var busyIds: Set<String> = []
    @State private var errorText: String?
    @State private var toast: String?
    @FocusState private var composerFocused: Bool

    private var reminderStatus: String { model.permissionsSnapshot["reminder"] ?? "unknown" }
    private var pendingItems: [TodoReminder] { items.filter { !$0.completed } }
    private var completedItems: [TodoReminder] { items.filter(\.completed) }
    private var visibleItems: [TodoReminder] { filter == .pending ? pendingItems : completedItems }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WhaleBackdrop().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if reminderStatus != "granted" { permissionCard }
                        filterBar
                        content
                        if let errorText { errorBanner(errorText) }
                        hint
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await reload() }
                .onTapGesture { composerFocused = false }

                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhaleTheme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(WhaleTheme.auroraGradient, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationBarHidden(true)
            .task { await reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await reload() }
                }
            }
            .onChange(of: voice.isRecording) { wasRecording, isRecording in
                guard wasRecording, !isRecording, voice.errorText == nil else { return }
                let preview = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard !voice.isRecording else { return }
                    let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft = text
                    submitText(text)
                }
            }
            .onDisappear { voice.stop() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WhaleIconTile(systemName: "checklist", size: 46, tint: WhaleTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("事情待办")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text("系统提醒事项 · 实时同步")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle(size: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭待办")
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要提醒事项权限", systemImage: "checklist")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)

            Text(reminderStatus == "denied"
                 ? "权限已被拒绝。请到 设置 › 隐私与安全性 › 提醒事项 中允许鲸鱼访问；返回后会自动刷新。"
                 : "允许后，这里会直接显示手机里真实的提醒事项，新增和勾选也会写回系统。")
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if reminderStatus == "denied" {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } else {
                    Task {
                        await model.requestPermission("reminder")
                        await reload()
                    }
                }
            } label: {
                Text(reminderStatus == "denied" ? "打开系统设置" : "允许访问提醒事项")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(WhaleTheme.auroraGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .whaleCard(padding: 16)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(.pending, count: pendingItems.count)
            filterButton(.completed, count: completedItems.count)
            Spacer(minLength: 0)
        }
    }

    private func filterButton(_ value: TodoFilter, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                Text(value.title)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((filter == value ? WhaleTheme.onAccent : WhaleTheme.muted).opacity(0.12), in: Capsule())
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filter == value ? WhaleTheme.onAccent : WhaleTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if filter == value {
                    Capsule().fill(WhaleTheme.auroraGradient)
                } else {
                    Capsule().fill(WhaleTheme.card.opacity(0.8))
                }
            }
            .overlay(Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            HStack(spacing: 9) {
                ProgressView().scaleEffect(0.8)
                Text("正在读取提醒事项…")
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 9) {
                ForEach(visibleItems) { item in
                    row(item)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .pending ? "checkmark.circle" : "archivebox")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(WhaleTheme.muted.opacity(0.7))
            Text(filter == .pending ? "还没有待办" : "还没有已完成事项")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text(filter == .pending ? "在下面写一句，直接加到系统提醒事项。" : "勾掉的事会出现在这里，可以再恢复。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func row(_ item: TodoReminder) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Button { toggle(item) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.completed ? WhaleTheme.success : WhaleTheme.line, lineWidth: 1.6)
                        .background(Circle().fill(item.completed ? WhaleTheme.success.opacity(0.14) : Color.clear))
                        .frame(width: 27, height: 27)
                    if busyIds.contains(item.id) {
                        ProgressView().scaleEffect(0.55)
                    } else if item.completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WhaleTheme.success)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busyIds.contains(item.id))
            .accessibilityLabel(item.completed ? "恢复 \(item.title)" : "完成 \(item.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.completed ? WhaleTheme.muted : WhaleTheme.ink)
                    .strikethrough(item.completed, color: WhaleTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    if let due = item.dueAt {
                        Label(dueText(due), systemImage: "clock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(dueColor(item, due))
                    } else {
                        Text("无日期")
                            .font(.system(size: 11))
                            .foregroundStyle(WhaleTheme.muted.opacity(0.75))
                    }
                    Text(item.listName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WhaleTheme.soft, in: Capsule())
                    if let notes = item.notes, !notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(WhaleTheme.muted.opacity(0.7))
                            .accessibilityLabel("有备注")
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                if item.completed {
                    Button("恢复为待办", systemImage: "arrow.uturn.backward") { toggle(item) }
                } else {
                    Button("标记完成", systemImage: "checkmark.circle") { toggle(item) }
                }
                Button("删除待办", systemImage: "trash", role: .destructive) { delete(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WhaleTheme.card.opacity(item.completed ? 0.55 : 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        )
        .contextMenu {
            Button("删除待办", systemImage: "trash", role: .destructive) { delete(item) }
        }
    }

    private var hint: some View {
        Text("直接写内容新增，或点麦克风说一句；输入「完成 买菜」勾掉，「删除 买菜」移除。")
            .font(.system(size: 11))
            .foregroundStyle(WhaleTheme.muted.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(WhaleTheme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WhaleTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var composer: some View {
        VStack(spacing: 7) {
            if let voiceError = voice.errorText {
                Label(voiceError, systemImage: "mic.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if voice.isRecording {
                voiceStrip
            }
            HStack(spacing: 8) {
                Button {
                    composerFocused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(voice.isRecording ? WhaleTheme.onAccent : WhaleTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            voice.isRecording ? WhaleTheme.danger : WhaleTheme.accentSoft,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音新增待办")

                TextField("写一件事，或点麦克风说", text: $draft)
                    .font(.system(size: 14))
                    .focused($composerFocused)
                    .submitLabel(.done)
                    .onSubmit { submitDraft() }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button { submitDraft() } label: {
                    ZStack {
                        Circle()
                            .fill(WhaleTheme.auroraGradient)
                            .frame(width: 34, height: 34)
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(WhaleTheme.onAccent)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(WhaleTheme.onAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("提交待办")
            }
            .padding(.leading, 13)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(WhaleTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            )

            Text("新增和完成都会直接写入系统「提醒事项」")
                .font(.system(size: 10))
                .foregroundStyle(WhaleTheme.muted.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var voiceStrip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(WhaleTheme.danger)
                .frame(width: 8, height: 8)
            Text(voice.transcript.isEmpty ? "正在听你说…" : voice.transcript)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button {
                voice.stop()
            } label: {
                Text("停止")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WhaleTheme.danger.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(WhaleTheme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(WhaleTheme.danger.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func submitDraft() {
        submitText(draft)
    }

    private func submitText(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isSubmitting else { return }
        errorText = nil
        isSubmitting = true

        Task {
            do {
                if let command = TodoQuickCommand.parse(raw) {
                    let message = try await run(command)
                    draft = ""
                    await reload(silent: true)
                    showToast(message)
                } else {
                    let parsed = TodoQuickParser.parseAdd(raw)
                    let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else {
                        throw ToolExecutionError(code: "empty_reminder", message: "写点具体内容再添加。")
                    }
                    let item = try await model.createTodoReminder(title: title, dueAt: parsed.dueAt)
                    draft = ""
                    filter = .pending
                    upsert(item)
                    await reload(silent: true)
                    if let dueAt = parsed.dueAt {
                        showToast("已加入 · \(dueText(dueAt))")
                    } else {
                        showToast("已加入 · \(item.title)")
                    }
                }
            } catch {
                errorText = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func run(_ command: TodoQuickCommand) async throws -> String {
        switch command {
        case .complete(let keyword):
            let target = try uniqueMatch(keyword, in: pendingItems, missing: "没有找到未完成的「\(keyword)」。")
            let updated = try await model.setTodoReminder(target, completed: true)
            upsert(updated)
            return "已完成 · \(target.title)"
        case .restore(let keyword):
            let target = try uniqueMatch(keyword, in: completedItems, missing: "没有找到已完成的「\(keyword)」。")
            let updated = try await model.setTodoReminder(target, completed: false)
            upsert(updated)
            return "已恢复 · \(target.title)"
        case .delete(let keyword):
            let target = try uniqueMatch(keyword, in: items, missing: "没有找到「\(keyword)」。")
            try await model.deleteTodoReminder(target)
            removeLocal(target.id)
            return "已删除 · \(target.title)"
        }
    }

    private func uniqueMatch(_ keyword: String, in source: [TodoReminder], missing: String) throws -> TodoReminder {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = source.filter { $0.title.caseInsensitiveCompare(key) == .orderedSame }
        let matches = exact.isEmpty ? source.filter { $0.title.localizedCaseInsensitiveContains(key) } : exact
        if matches.isEmpty { throw ToolExecutionError(code: "reminder_not_found", message: missing) }
        if matches.count > 1 {
            let names = matches.prefix(3).map(\.title).joined(separator: "、")
            throw ToolExecutionError(
                code: "ambiguous_reminder",
                message: "有 \(matches.count) 条匹配「\(key)」：\(names)。请写更完整的标题。"
            )
        }
        return matches[0]
    }

    private func toggle(_ item: TodoReminder) {
        guard !busyIds.contains(item.id) else { return }
        busyIds.insert(item.id)
        errorText = nil
        Task {
            do {
                let updated = try await model.setTodoReminder(item, completed: !item.completed)
                upsert(updated)
                await reload(silent: true)
                showToast(item.completed ? "已恢复 · \(item.title)" : "已完成 · \(item.title)")
            } catch {
                errorText = error.localizedDescription
            }
            busyIds.remove(item.id)
        }
    }

    private func delete(_ item: TodoReminder) {
        guard !busyIds.contains(item.id) else { return }
        busyIds.insert(item.id)
        errorText = nil
        Task {
            do {
                try await model.deleteTodoReminder(item)
                removeLocal(item.id)
                await reload(silent: true)
                showToast("已删除 · \(item.title)")
            } catch {
                errorText = error.localizedDescription
            }
            busyIds.remove(item.id)
        }
    }

    private func reload(silent: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        if !silent { errorText = nil }
        defer { isLoading = false }
        do {
            items = try await model.loadTodoReminders(includeCompleted: true)
            model.refreshPermissions()
        } catch {
            let permissionDenied = (error as? ToolExecutionError)?.code == "permission_denied"
            if !permissionDenied || items.isEmpty {
                errorText = error.localizedDescription
            }
            model.refreshPermissions()
        }
    }

    private func upsert(_ item: TodoReminder) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        items.sort { left, right in
            if left.completed != right.completed { return !left.completed }
            switch (left.dueAt, right.dueAt) {
            case let (leftDate?, rightDate?): return leftDate < rightDate
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }
    }

    private func removeLocal(_ id: String) {
        items.removeAll { $0.id == id }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        let current = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == current {
                withAnimation(.easeIn(duration: 0.18)) { toast = nil }
            }
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func dueColor(_ item: TodoReminder, _ date: Date) -> Color {
        if item.completed { return WhaleTheme.muted }
        if date < Date() { return WhaleTheme.danger }
        if Calendar.current.isDateInToday(date) { return WhaleTheme.coral }
        return WhaleTheme.moon
    }
}

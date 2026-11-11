import SwiftUI
import UIKit

/// The conversation starter. Tapping 对话 lands here: a real chat surface with
/// a rotating daily note, immediate prompts and the state the phone actually has.
struct WhaleHomeCanvas: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void
    let onOpenMusic: () -> Void
    let onOpenTodo: () -> Void
    @State private var weatherDays: [WeatherDaySummary] = []
    @State private var weatherLocation = ""
    @State private var weatherLoading = false
    @State private var weatherError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dailyQuote
                suggestions
                weatherCard
                todayCard
                if model.isBusy {
                    busyCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28 + bottomInset)
        }
        .scrollIndicators(.hidden)
        .onTapGesture { dismissKeyboard() }
        .task { await loadWeatherIfNeeded() }
        .onChange(of: model.permissionsSnapshot["location"]) { _, status in
            guard status == "granted" else { return }
            Task { await loadWeather(force: true) }
        }
    }

    // MARK: - Daily quote

    private static let dailyQuotes: [String] = [
        "今天也慢慢来，鲸鱼陪你一起往前。",
        "你已经比昨天更靠近想去的地方。",
        "先照顾好自己，再去照顾世界。",
        "慢一点没关系，方向对就好。",
        "今天的努力，会在某天悄悄回报你。",
        "允许自己休息，休息也是前进的一部分。",
        "你不需要完美，只需要继续。",
        "把小事做好，日子就会亮起来。",
        "心里有光，走到哪里都不算黑。",
        "今天遇到的难题，会成为明天的底气。",
        "深呼吸，事情一件一件来。",
        "你值得被温柔对待，先从自己开始。",
        "别急着证明自己，时间会替你说话。",
        "每一次坚持，都在悄悄改变你。",
        "今天也要记得，为自己留一点喜欢。",
        "你已经做得很好，真的。",
        "世界很大，你的节奏刚刚好。",
        "把注意力放回当下，一切会清晰起来。",
        "愿你今天被小事治愈，被好消息敲门。",
        "不必追赶别人，你有自己的海。",
        "再普通的一天，也值得认真过。",
        "你正在成为更好的自己，别怀疑。",
        "累了就靠岸，鲸鱼一直在。",
        "今天的好运，正在路上。",
        "把烦恼交给海风，把力气留给自己。",
        "你走的每一步，都算数。",
        "心里装一点期待，日子就有了光。",
        "别怕慢，怕的是停在原地责怪自己。",
        "今天也要好好吃饭，好好睡觉。",
        "无论今天怎样，明天仍有新的海。"
    ]

    private static let slotOpeners: [String] = [
        "夜深了", "凌晨了", "天快亮了", "早上好", "上午好", "快到中午",
        "中午好", "午后好", "下午好", "傍晚好", "晚上好", "夜里好"
    ]

    private var dailyQuote: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let quote = Self.quote(at: context.date)
            HStack(alignment: .top, spacing: 10) {
                WhaleMarkView(size: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("鲸鱼对你说")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(WhaleTheme.accent)
                    Text(quote)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [WhaleTheme.accent.opacity(0.10), WhaleTheme.card.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }

    private static func quote(at date: Date) -> String {
        let calendar = Calendar.current
        let dayCount = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = ((dayCount % dailyQuotes.count) + dailyQuotes.count) % dailyQuotes.count
        let slot = min(slotOpeners.count - 1, calendar.component(.hour, from: date) / 2)
        return "\(slotOpeners[slot])，\(dailyQuotes[index])"
    }

    // MARK: - Music

    private var musicQuickSubtitle: String {
        guard let track = model.playback.track else {
            return "曲库 · \(model.musicPlayMode.title)"
        }
        return (model.playback.isPlaying ? "正在播放 · " : "") + track.title
    }

    // MARK: - Prompts

    private var suggestions: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            quickCard(
                title: "附近找店",
                subtitle: "环境·预算·可订位",
                icon: "mappin.and.ellipse",
                tint: WhaleTheme.accent,
                soft: WhaleTheme.accentSoft
            ) {
                send("帮我找附近安静、适合两个人吃饭的地方，按距离和价格筛选。")
            }

            quickCard(
                title: "事情待办",
                subtitle: "新增·勾选",
                icon: "square.stack.3d.up.fill",
                tint: WhaleTheme.moon,
                soft: WhaleTheme.blueSoft
            ) {
                onOpenTodo()
            }

            quickCard(
                title: "音乐",
                subtitle: musicQuickSubtitle,
                icon: "music.note",
                tint: WhaleTheme.coral,
                soft: WhaleTheme.amberSoft,
                action: onOpenMusic
            )

            quickCard(
                title: "记录回顾",
                subtitle: "提醒·日程·操作",
                icon: "clock.arrow.circlepath",
                tint: WhaleTheme.moon,
                soft: WhaleTheme.blueSoft
            ) {
                onOpenRecords()
            }
        }
    }

    private func quickCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        soft: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(soft)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WhaleTheme.card.opacity(0.88))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    // MARK: - Weather

    private var locationStatus: String {
        model.permissionsSnapshot["location"] ?? "unknown"
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhaleTheme.coral)
                Text("天气详情")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer(minLength: 6)
                if !weatherLocation.isEmpty {
                    Text(weatherLocation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }
                if weatherLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(WhaleTheme.accent)
                } else if locationStatus == "granted", !weatherDays.isEmpty {
                    Button {
                        Task { await loadWeather(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WhaleTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新天气")
                }
            }

            if locationStatus != "granted" {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WhaleTheme.coral, WhaleTheme.coral.opacity(0.12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locationStatus == "denied" ? "定位权限未开启" : "查看所在地的真实天气")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WhaleTheme.ink)
                        Text("授权后显示温度、降水和穿衣建议。没有数据时不会生成示例天气。")
                            .font(.system(size: 11))
                            .foregroundStyle(WhaleTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }

                Button(locationStatus == "denied" ? "去系统设置" : "开启定位并查看") {
                    if locationStatus == "denied" {
                        model.openSystemSettings()
                    } else {
                        Task {
                            await model.requestPermission("location")
                            if model.permissionsSnapshot["location"] == "granted" {
                                await loadWeather(force: true)
                            }
                        }
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WhaleTheme.accent)
                .buttonStyle(.plain)
            } else if let weatherError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂时没有取得天气数据")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                    Text(weatherError)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重新查询") {
                        Task { await loadWeather(force: true) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .buttonStyle(.plain)
                }
            } else if let today = weatherDays.first {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: today.icon)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WhaleTheme.coral, WhaleTheme.moon)
                        .font(.system(size: 35, weight: .medium))
                        .frame(width: 54, height: 54)
                        .background(WhaleTheme.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(today.dayLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(WhaleTheme.muted)
                        Text(today.summary)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(WhaleTheme.ink)
                        HStack(spacing: 8) {
                            Text(today.temperatureText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(WhaleTheme.ink)
                            if let rain = today.precipitationText {
                                Text(rain)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(WhaleTheme.moon)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(WhaleTheme.moon.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !today.advice.isEmpty {
                    Text(today.advice)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if weatherDays.count > 1 {
                    Rectangle()
                        .fill(WhaleTheme.line)
                        .frame(height: 0.5)

                    VStack(spacing: 9) {
                        ForEach(Array(weatherDays.dropFirst().prefix(3))) { day in
                            HStack(spacing: 9) {
                                Text(day.dayLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WhaleTheme.muted)
                                    .frame(width: 48, alignment: .leading)
                                Image(systemName: day.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WhaleTheme.coral)
                                    .frame(width: 18)
                                Text(day.summary)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WhaleTheme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if let rain = day.precipitationText {
                                    Text(rain)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(WhaleTheme.moon)
                                }
                                Text(day.temperatureText)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WhaleTheme.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                HStack(spacing: 5) {
                    Spacer()
                    Text("Open-Meteo · 真实预报")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.75))
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WhaleTheme.accent)
                    Text("正在读取所在地天气…")
                        .font(.system(size: 12))
                        .foregroundStyle(WhaleTheme.muted)
                    Spacer(minLength: 0)
                }
                .frame(height: 48)
            }
        }
        .whaleCard(padding: 16)
    }

    private func loadWeatherIfNeeded() async {
        guard locationStatus == "granted", weatherDays.isEmpty, !weatherLoading else { return }
        await loadWeather(force: false)
    }

    private func loadWeather(force: Bool) async {
        guard locationStatus == "granted" else { return }
        guard !weatherLoading else { return }
        if !force, !weatherDays.isEmpty { return }
        weatherLoading = true
        weatherError = nil
        defer { weatherLoading = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 3, to: start) ?? start.addingTimeInterval(259_200)
        do {
            let data = try await WeatherExecutor().query(arguments: [
                "startAt": .string(ToolDate.iso(start)),
                "endAt": .string(ToolDate.iso(end)),
                "timezone": .string(TimeZone.current.identifier)
            ])
            let days = WeatherDaySummary.list(from: data)
            guard !days.isEmpty else {
                weatherError = "天气接口本次没有返回逐日预报，请稍后重试。"
                return
            }
            weatherDays = days
            weatherLocation = data.objectValue?.optionalString("locationName") ?? "当前位置"
        } catch {
            weatherError = error.localizedDescription
        }
    }

    // MARK: - Real calendar

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY · \(todayLabel)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(WhaleTheme.muted)
                    Text(calendarGranted ? todayTitle : "今天还没有读取日历")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                }
                Spacer(minLength: 8)
                if calendarGranted {
                    Text(todayStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WhaleTheme.coral)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(WhaleTheme.coral.opacity(0.11), in: Capsule())
                }
            }

            if calendarGranted {
                if todayEvents.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WhaleTheme.coral)
                            .frame(width: 38, height: 38)
                            .background(WhaleTheme.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("今天没有日程")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WhaleTheme.ink)
                            Text(nextEventText)
                                .font(.system(size: 11))
                                .foregroundStyle(WhaleTheme.muted)
                                .lineLimit(2)
                        }
                    }
                } else {
                    ForEach(todayEvents.prefix(4)) { event in
                        eventRow(event)
                    }
                    if todayEvents.count > 4 {
                        Text("还有 \(todayEvents.count - 4) 项，去记录里查看")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WhaleTheme.muted)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("授权后显示真实日程，不会生成示例事件。")
                            .font(.system(size: 12))
                            .foregroundStyle(WhaleTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("读取我的日历") {
                            Task { await model.requestPermission("calendarRead") }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.accent)
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.6))
                }
            }
        }
        .whaleCard(padding: 17)
    }

    private func eventRow(_ event: CalendarEventPreview) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 4) {
                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WhaleTheme.muted)
                Circle()
                    .fill(WhaleTheme.accent)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                Text(event.calendarTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
    }

    private var calendarGranted: Bool {
        model.permissionsSnapshot["calendarRead"] == "granted"
    }

    private var todayEvents: [CalendarEventPreview] {
        model.upcomingEvents
            .filter { Calendar.current.isDateInToday($0.startAt) }
            .sorted { $0.startAt < $1.startAt }
    }

    private var todayTitle: String {
        if todayEvents.isEmpty { return "今天暂无安排" }
        return "今天还剩 \(todayEvents.count) 件事"
    }

    private var todayStatusText: String {
        if todayEvents.isEmpty { return "无日程" }
        return "\(todayEvents.count) 件"
    }

    private var todayLabel: String {
        Date().formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private var nextEventText: String {
        guard let next = model.upcomingEvents.sorted(by: { $0.startAt < $1.startAt }).first else {
            return "接下来 7 天也没有安排。"
        }
        return "下一项：\(next.startAt.formatted(.dateTime.month().day().hour().minute())) · \(next.title)"
    }

    // MARK: - Busy

    private var busyCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(WhaleTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("鲸鱼正在处理")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(model.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .whaleCard(padding: 14)
    }

    private func send(_ text: String) {
        dismissKeyboard()
        Task { await model.send(text: text) }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

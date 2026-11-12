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
    let onOpenDiscover: (DiscoverChannel) -> Void
    let onOpenConversation: () -> Void
    @State private var weatherDays: [WeatherDaySummary] = []
    @State private var weatherLocation = ""
    @State private var weatherLoading = false
    @State private var weatherError: String?
    @State private var weatherExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                weatherCard
                dailyQuote
                categoryGrid
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
        "别急着一次翻过整座山，把今天这一步踩稳，路就会一点点亮起来。",
        "你不需要时刻强大，只要在每一次想放弃的时候，再为自己多坚持一分钟。",
        "真正的成长，不是永远顺风，而是风浪来了，你依然知道该往哪里走。",
        "今天多做的每一点努力，都会在未来某个关键时刻，变成你手里的底牌。",
        "允许自己慢一点，但别停下来。你走的每一步，都在把想要的生活拉近。",
        "把焦虑换成行动，把犹豫换成出发。很多答案，走着走着就清楚了。",
        "你已经在路上了，别总盯着还差多远，也看看自己已经走了多远。",
        "先把自己照顾好，再去赢下今天。状态在线，机会才会看得见你。",
        "困难不是来拦住你的，是来提醒你：这次跨过去，你会比昨天更强。",
        "别把时间花在怀疑自己上，你真正需要做的，是把下一件事做好。",
        "今天也要相信，认真生活的人不会被辜负。你的坚持，正在悄悄积攒好运。",
        "把大目标拆成小行动，先完成眼前这一件。掌控感，就是这样一点点回来的。",
        "不用和任何人比速度，你有自己的节奏，也有属于自己的终点。",
        "你可以累，可以停一会儿，但别否定自己。能走到这里，你已经很了不起。",
        "把注意力收回到当下，做好能做的事。今天稳住了，明天自然会更有底气。",
        "愿你今天有破局的勇气，也有接受不完美的松弛。全力以赴，也允许喘息。",
        "好运从来不是等来的，它藏在你每一次认真、每一次坚持、每一次不放弃里。",
        "别怕现在辛苦，所有向上走的路都不轻松。你正在变成更厉害的人。",
        "今天也要给自己一点信心：你处理过的难题，已经证明了你的能力。",
        "先行动，再调整。别等万事俱备，很多机会只奖励第一个出发的人。",
        "你值得拥有更好的生活，也值得为它认真努力。今天，再向它靠近一点。",
        "把抱怨的时间拿来解决问题，把担心的时间拿来准备。你会越来越从容。",
        "真正的安全感，来自你知道自己在变强。今天学一点、做一点，就是进步。",
        "别让一时的情绪，替你做长期的决定。深呼吸，稳住节奏，你还有很长的路。",
        "无论今天顺不顺，都别轻易给自己下结论。你只是还在路上，不是已经到终点。",
        "把每一步走扎实，把每件事做完整。时间会把你的认真，变成看得见的成绩。",
        "愿你今天清醒、坚定、有执行力，也保留一点热爱和浪漫。这样的你很有力量。",
        "别小看每天的一点点进步，一年之后，它会变成你自己都惊讶的改变。",
        "今天也要好好吃饭、好好睡觉、好好做事。把日子过稳，就是最了不起的能力。",
        "不管现在多难，都请再相信自己一次。你熬过的夜，终会照亮你前行的路。"
    ]

    private static let slotOpeners: [String] = [
        "夜深了", "凌晨了", "天快亮了", "早上好", "上午好", "快到中午",
        "中午好", "午后好", "下午好", "傍晚好", "晚上好", "夜里好"
    ]

    private var dailyQuote: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let quote = Self.quote(at: context.date)
            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpenConversation) {
                    WhaleMarkView(size: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("进入对话")

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("BOSS · 正能量鸡汤")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(WhaleTheme.accentDeep)
                        Spacer(minLength: 0)
                        Text("30天不重样")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(WhaleTheme.muted.opacity(0.85))
                    }
                    Text(quote)
                        .font(.system(size: 15, weight: .regular))
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
                            colors: [WhaleTheme.accent.opacity(0.10), WhaleTheme.card.opacity(0.90)],
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
        return "BOSS，\(slotOpeners[slot])。\(dailyQuotes[index])"
    }

    // MARK: - Music

    private var musicQuickSubtitle: String {
        guard let track = model.playback.track else {
            return "曲库 · \(model.musicPlayMode.title)"
        }
        return (model.playback.isPlaying ? "正在播放 · " : "") + track.title
    }

    private var musicBadge: String {
        guard model.playback.track != nil else { return "曲库" }
        return model.playback.isPlaying ? "正在播放" : "已暂停"
    }

    // MARK: - Prompts

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            discoverCard(
                title: "AI科技",
                subtitle: "模型 · 产品 · 前沿",
                badge: "真实来源",
                icon: "sparkles",
                gradient: WhaleTheme.heroGradient
            ) {
                onOpenDiscover(.ai)
            }

            discoverCard(
                title: "A股自选",
                subtitle: "指数 · 个股 · 日 K",
                badge: "延迟 15 分钟",
                icon: "chart.line.uptrend.xyaxis",
                gradient: LinearGradient(
                    colors: [WhaleTheme.moon, WhaleTheme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) {
                onOpenDiscover(.market)
            }

            discoverCard(
                title: "游戏行情",
                subtitle: "资讯 · 免费榜 · 畅销榜",
                badge: "App Store",
                icon: "gamecontroller.fill",
                gradient: WhaleTheme.gameGradient
            ) {
                onOpenDiscover(.game)
            }

            discoverCard(
                title: "我的音乐",
                subtitle: musicQuickSubtitle,
                badge: musicBadge,
                icon: "music.note",
                gradient: WhaleTheme.musicGradient,
                action: onOpenMusic
            )

            discoverCard(
                title: "时事新闻",
                subtitle: "要闻 · 权威 RSS",
                badge: "真实来源",
                icon: "newspaper.fill",
                gradient: WhaleTheme.headlineGradient
            ) {
                onOpenDiscover(.headline)
            }

            discoverCard(
                title: "微博热搜",
                subtitle: "实时榜 · 公开数据",
                badge: "实时",
                icon: "flame.fill",
                gradient: WhaleTheme.weiboGradient
            ) {
                onOpenDiscover(.weibo)
            }
        }
    }

    private func discoverCard(
        title: String,
        subtitle: String,
        badge: String,
        icon: String,
        gradient: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 4)
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 2)
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
            .background(gradient, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
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
                Button {
                    withAnimation(.snappy(duration: 0.2)) { weatherExpanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: today.icon)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(WhaleTheme.coral, WhaleTheme.moon)
                            .font(.system(size: 28, weight: .medium))
                            .frame(width: 46, height: 46)
                            .background(WhaleTheme.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(today.summary)
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(WhaleTheme.ink)
                                Text(today.temperatureText)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WhaleTheme.ink)
                            }
                            HStack(spacing: 5) {
                                Text(weatherLocation.isEmpty ? "当前位置" : weatherLocation)
                                    .lineLimit(1)
                                if let rain = today.precipitationText {
                                    Text("·")
                                    Text(rain)
                                }
                                Text("·")
                                Text(today.dayLabel)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WhaleTheme.muted)
                        }

                        Spacer(minLength: 4)

                        if weatherLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(WhaleTheme.accent)
                        } else {
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(weatherExpanded ? "收起" : (weatherDays.count > 1 ? "\(weatherDays.count)日预报" : "详情"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(WhaleTheme.muted)
                                Image(systemName: weatherExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WhaleTheme.muted.opacity(0.8))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("天气详情")

                if weatherExpanded {
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
                    Text("Open-Meteo · 真实预报")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.75))
                    Spacer()
                    Button {
                        Task { await loadWeather(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新天气")
                }
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

            HStack {
                Spacer()
                Button { onOpenRecords() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("记录回顾")
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WhaleTheme.accent)
                .buttonStyle(.plain)
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

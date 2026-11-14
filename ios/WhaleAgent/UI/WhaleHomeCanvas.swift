import SwiftUI
import UIKit

/// The conversation starter. Tapping 对话 lands here: a real chat surface with
/// a rotating daily note, immediate prompts and the state the phone actually has.
@MainActor
struct WhaleHomeCanvas: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void
    let onOpenMusic: () -> Void
    let onOpenTodo: () -> Void
    let onOpenDiscover: (DiscoverChannel) -> Void
    let onOpenConversation: () -> Void
    @State private var weatherDays: [WeatherDaySummary] = []
    @State private var weather: WeatherSnapshot?
    @State private var weatherLocation = ""
    @State private var weatherLoading = false
    @State private var weatherError: String?
    @AppStorage("whale.home.showQuote") private var showQuote = true
    @State private var quoteExpanded = false
    @State private var showWeatherDetail = false
    @State private var homeTodos: [TodoReminder] = []
    @StateObject private var digest = HomeDigestModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var weatherExpanded = ProcessInfo.processInfo.environment["WHALE_DEMO_WEATHER"] == "1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showQuote { dailyQuote }
                todayCard
                InlinePlaybackView(model: model, onOpen: onOpenMusic)
                categoryGrid
                AssistantActivityView(model: model)
                if !model.messages.isEmpty {
                    Button(action: onOpenConversation) {
                        Label("继续最近对话", systemImage: "bubble.left.and.bubble.right")
                            .font(.body.weight(.medium)).whaleTouchTarget()
                    }.foregroundStyle(WhaleTheme.accent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .background(WhaleBackdrop())
            .task {
                await loadWeatherIfNeeded()
                await loadHomeTodos()
                await model.refreshDashboard()
                await digest.prime()
            }
            .onChange(of: model.permissionsSnapshot) { _, _ in Task { await loadWeatherIfNeeded(); await loadHomeTodos() } }
            .sheet(isPresented: $showWeatherDetail) {
                NavigationStack {
                    ScrollView { weatherCard.padding(20) }.background(WhaleTheme.background)
                        .navigationTitle("天气详情").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showWeatherDetail = false } } }
                }
            }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用操作").font(.headline).foregroundStyle(WhaleTheme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array(DiscoverChannel.allCases.enumerated()), id: \.element) { offset, channel in
                    Button {
                        if channel == .music { onOpenMusic() }
                        else { onOpenDiscover(channel) }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: channel.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                                Spacer(minLength: 4)

                                Text(channel.title)
                                    .whaleFont(size: 17, weight: .bold, design: .rounded)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.top, 1)
                            }

                            Spacer(minLength: 8)

                            RollingSummaryText(
                                lines: summaryLines(for: channel),
                                delay: Double(offset) * 0.55,
                                maxLines: 1,
                                fontSize: 11
                            )
                        }
                        .foregroundStyle(.white).padding(12)
                            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                            .background {
                                let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
                                shape.fill(channel.entryGradient).overlay(shape.fill(.black.opacity(0.30)))
                            }
                            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
                            .whaleSoftElevation()
                    }.buttonStyle(.plain).accessibilityLabel(channel.title)
                        .accessibilityIdentifier("home-channel-" + channel.rawValue)
                }
            }
        }
    }

    private func summaryLines(for channel: DiscoverChannel) -> [String] {
        if channel == .music { return musicSummaryLines }
        let live = digest.lines[channel] ?? []
        return live.isEmpty ? [channel.subtitle] : live
    }

    private var musicSummaryLines: [String] {
        if let track = model.playback.track {
            let state = model.playback.state == "playing" ? "正在播放" : "已暂停"
            var rows = ["\(state) · \(track.title) — \(track.artist)"]
            if !model.musicTracks.isEmpty {
                rows.append("曲库 \(model.musicTracks.count) 首 · \(model.musicPlayMode.title)")
            }
            return rows
        }
        return ["系统资料库 · 本地音乐", "点按进入播放控制"]
    }
    private var todayWeather: some View {
        Button {
            if locationStatus == "granted", weatherDays.isEmpty, !weatherLoading {
                Task { await loadWeather(force: true) }
            } else {
                weatherExpanded = true; showWeatherDetail = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: weatherDays.first?.icon ?? "cloud.sun").foregroundStyle(WhaleTheme.accent)
                if weatherLoading && weatherDays.isEmpty { Text("天气查询中…") }
                else if let day = weatherDays.first {
                    Text("\(weatherLocation) · \(weather?.current?.summary ?? day.summary) · \(currentTemperatureText)")
                } else { Text(locationStatus == "granted" ? "刷新天气" : "查看天气") }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption)
            }.font(.subheadline).foregroundStyle(WhaleTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).accessibilityIdentifier("home-today-weather")
            .accessibilityHint("查看天气详情；天气未获取时重新查询")
    }
    private var dailyQuote: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { quoteExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "quote.opening").font(.title3).foregroundStyle(WhaleTheme.accent)
                    Text(DailyQuote.text(at: context.date)).whaleFont(size: 16, weight: .medium)
                        .foregroundStyle(WhaleTheme.ink).lineSpacing(3)
                        .lineLimit(quoteExpanded || textSize.isAccessibilitySize ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: quoteExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(WhaleTheme.muted)
                }.frame(minHeight: 44, alignment: .center).whaleCard(padding: 14)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("home-inspiration-card")
                .accessibilityHint("点击展开每日一句")
                .contextMenu { Button("隐藏今日一句") { showQuote = false } }
        }
    }
    private func loadHomeTodos() async {
        guard model.permissionsSnapshot["reminder"] == "granted" else { homeTodos = []; return }
        homeTodos = (try? await model.loadTodoReminders(includeCompleted: false)) ?? homeTodos
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
                        .whaleFont(size: 28, weight: .medium)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(WhaleTheme.coral, WhaleTheme.coral.opacity(0.12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locationStatus == "denied" ? "定位权限未开启" : "查看所在地的真实天气")
                            .whaleFont(size: 17, weight: .semibold)
                            .foregroundStyle(WhaleTheme.ink)
                        Text("授权后显示温度、降水和穿衣建议。")
                            .whaleFont(size: 13)
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
                .whaleFont(size: 14, weight: .semibold)
                .foregroundStyle(WhaleTheme.accent)
                .buttonStyle(.plain)
            } else if let weatherError {
                VStack(alignment: .leading, spacing: 7) {
                    Text("暂时没有取得天气数据")
                        .whaleFont(size: 16, weight: .semibold)
                        .foregroundStyle(WhaleTheme.ink)
                    Text(weatherError)
                        .whaleFont(size: 13)
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重新查询") {
                        Task { await loadWeather(force: true) }
                    }
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.accent)
                    .buttonStyle(.plain)
                }
            } else if let today = weatherDays.first {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { weatherExpanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: today.icon)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(WhaleTheme.coral, WhaleTheme.moon)
                            .whaleFont(size: 31, weight: .medium)
                            .frame(width: 52, height: 52)
                            .background(WhaleTheme.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(weather?.current?.summary ?? today.summary)
                                    .whaleFont(size: 20, weight: .bold, design: .rounded)
                                    .foregroundStyle(WhaleTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                                Text(currentTemperatureText)
                                    .whaleFont(size: 34, weight: .bold, design: .rounded)
                                    .foregroundStyle(WhaleTheme.ink)
                            }
                            Text(weatherMetaLine(today))
                            .whaleFont(size: 13, weight: .medium)
                            .foregroundStyle(WhaleTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 4)

                        if weatherLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(WhaleTheme.accent)
                        } else {
                            Image(systemName: weatherExpanded ? "chevron.up" : "chevron.down")
                                .whaleFont(size: 13, weight: .bold)
                                .foregroundStyle(WhaleTheme.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("天气详情")

                if !weatherExpanded, let current = weather?.current {
                    weatherQuickStats(current)
                }

                if weatherExpanded {
                if let hours = weather?.hours, !hours.isEmpty {
                    Rectangle()
                        .fill(WhaleTheme.line)
                        .frame(height: 0.5)
                    hourlyStrip(hours)
                }

                if let sun = weather?.sun {
                    HStack(spacing: 18) {
                        Label("日出 \(sun.sunriseText)", systemImage: "sunrise.fill")
                        Label("日落 \(sun.sunsetText)", systemImage: "sunset.fill")
                        Spacer(minLength: 0)
                    }
                    .whaleFont(size: 13, weight: .medium)
                    .foregroundStyle(WhaleTheme.muted)
                }

                if let current = weather?.current, !weatherDays.isEmpty {
                    Rectangle()
                        .fill(WhaleTheme.line)
                        .frame(height: 0.5)
                    metricsGrid(current, today: today)
                }

                HStack(spacing: 5) {
                    Text("Open-Meteo · 真实预报")
                        .whaleFont(size: 13, weight: .medium)
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
                    .whaleFont(size: 13, weight: .semibold)
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
                        .whaleFont(size: 14)
                        .foregroundStyle(WhaleTheme.muted)
                    Spacer(minLength: 0)
                }
                .frame(height: 48)
            }
        }
        .whaleCard(padding: 18)
    }

    private var currentTemperatureText: String {
        if let value = weather?.current?.temperatureC {
            return "\(Int(value.rounded()))°"
        }
        return weatherDays.first?.temperatureText ?? "—"
    }

    private func weatherMetaLine(_ today: WeatherDaySummary) -> String {
        var parts = [weatherLocation.isEmpty ? "当前位置" : weatherLocation, today.temperatureText]
        if let rain = today.precipitationText {
            parts.append(rain)
        }
        return parts.joined(separator: " · ")
    }

    private func weatherQuickStats(_ current: WeatherSnapshot.Current) -> some View {
        HStack(spacing: 10) {
            weatherQuickStat(
                "体感",
                current.apparentC.map { "\(Int($0.rounded()))°" } ?? "—",
                icon: "thermometer.medium"
            )
            weatherQuickStat(
                "湿度",
                current.humidity.map { "\(Int($0.rounded()))%" } ?? "—",
                icon: "humidity.fill"
            )
            weatherQuickStat(
                "风速",
                current.windKph.map { String(format: "%.0f km/h", $0) } ?? "—",
                icon: "wind"
            )
        }
        .padding(10)
        .background(WhaleTheme.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { weatherExpanded.toggle() }
        }
    }

    private func weatherQuickStat(_ label: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .whaleFont(size: 13, weight: .semibold)
                Text(label)
                    .whaleFont(size: 13, weight: .medium)
            }
            .foregroundStyle(WhaleTheme.muted)
            Text(value)
                .whaleFont(size: 15, weight: .semibold, design: .rounded)
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hourlyStrip(_ hours: [WeatherSnapshot.Hour]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("逐小时预报")
                .whaleFont(size: 14, weight: .semibold)
                .foregroundStyle(WhaleTheme.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(hours) { hour in
                        VStack(spacing: 5) {
                            Text(hour.hourLabel)
                                .whaleFont(size: 13, weight: .medium)
                                .foregroundStyle(WhaleTheme.muted)
                            Image(systemName: hour.icon)
                                .whaleFont(size: 17, weight: .medium)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(hour.isDay ? WhaleTheme.coral : WhaleTheme.moon, WhaleTheme.moon.opacity(0.5))
                            Text(hour.temperatureC.map { "\(Int($0.rounded()))°" } ?? "—")
                                .whaleFont(size: 15, weight: .bold, design: .rounded)
                                .foregroundStyle(WhaleTheme.ink)
                            Text(hour.precipitationChance.map { "\(Int($0.rounded()))%" } ?? " ")
                                .whaleFont(size: 13, weight: .medium)
                                .foregroundStyle(WhaleTheme.moon)
                        }
                        .frame(width: 42)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func metricsGrid(_ current: WeatherSnapshot.Current, today: WeatherDaySummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCell("体感", current.apparentC.map { "\(Int($0.rounded()))°" } ?? "—", "thermometer.medium")
            metricCell("湿度", current.humidity.map { "\(Int($0.rounded()))%" } ?? "—", "humidity.fill")
            metricCell("风速", current.windKph.map { String(format: "%.0f km/h", $0) } ?? "—", "wind")
            metricCell("降水概率", today.precipitationText?.replacingOccurrences(of: "降水 ", with: "") ?? "—", "drop.fill")
            metricCell("紫外线", today.uvIndexText ?? "—", "sun.max.fill")
            metricCell("空气质量", weather?.air.map { "\($0.aqiText) \($0.levelText)" } ?? "—", "aqi.medium")
        }
    }

    private func metricCell(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .whaleFont(size: 13, weight: .semibold)
                Text(label)
                    .whaleFont(size: 13, weight: .medium)
            }
            .foregroundStyle(WhaleTheme.muted)
            Text(value)
                .whaleFont(size: 16, weight: .semibold, design: .rounded)
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(WhaleTheme.soft.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start.addingTimeInterval(518_400)
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
            weather = WeatherSnapshot.from(data)
            weatherLocation = data.objectValue?.optionalString("locationName") ?? "当前位置"
        } catch {
            weatherError = error.localizedDescription
        }
    }

    // MARK: - Real calendar

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今天 · \(todayLabel)").font(.headline).foregroundStyle(WhaleTheme.ink)
                Spacer()
                Button("查看待办", action: onOpenTodo).font(.subheadline).whaleTouchTarget()
            }
            todayWeather
            if model.isDashboardLoading { ProgressView("正在读取安排…").font(.subheadline) }
            if calendarGranted {
                if todayEvents.isEmpty { Text("今天暂无日程").font(.body).foregroundStyle(WhaleTheme.muted) }
                ForEach(todayEvents.filter { $0.endAt > Date() }.prefix(2)) { event in eventRow(event) }
            } else {
                Button("连接日历，查看今天安排") { Task { await model.requestPermission("calendarRead") } }
                    .font(.body).foregroundStyle(WhaleTheme.accent).frame(minHeight: 44)
            }
            ForEach(homeTodos.filter { !$0.completed }.prefix(2)) { item in
                Button(action: onOpenTodo) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(WhaleTheme.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.body).foregroundStyle(WhaleTheme.ink).lineLimit(2)
                            if let due = item.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(WhaleTheme.muted) }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
            if let error = model.dashboardError { Text(error).font(.subheadline).foregroundStyle(WhaleTheme.warm) }
        }.whaleCard().accessibilityElement(children: .contain).accessibilityIdentifier("home-today-card")
    }

    private func eventRow(_ event: CalendarEventPreview) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 4) {
                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                    .whaleFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(WhaleTheme.muted)
                Circle()
                    .fill(WhaleTheme.accent)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                Text(event.calendarTitle)
                    .whaleFont(size: 13)
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
            .filter { Calendar.current.isDateInToday($0.startAt) && $0.endAt > Date() }
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
                    .whaleFont(size: 13, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                Text(model.statusLine)
                    .whaleFont(size: 13)
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

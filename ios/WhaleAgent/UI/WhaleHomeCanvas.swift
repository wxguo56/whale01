import SwiftUI
import UIKit

/// The conversation starter. Tapping 对话 lands here: a real chat surface with
/// a greeting, immediate prompts and the calendar state the phone actually has.
struct WhaleHomeCanvas: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void
    let onOpenMusic: () -> Void
    let onOpenTodo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                greeting
                musicEntry
                suggestions
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
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .top, spacing: 9) {
            WhaleMarkView(size: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(greetingHeadline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("说一句，我来办。找地点、查天气、排日程，也可以直接让我记一件事。")
                    .font(.system(size: 14))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                WhaleTheme.bubble,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .strokeBorder(WhaleTheme.line.opacity(0.8), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 5)

            Spacer(minLength: 0)
        }
    }

    private var greetingHeadline: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<6: return "夜深了，我在。"
        case 6..<11: return "早上好，今天交给我。"
        case 11..<14: return "中午好，想先办哪件？"
        case 14..<18: return "下午好，接下来做什么？"
        default: return "晚上好，我在听。"
        }
    }

    // MARK: - Music entry

    private var musicEntry: some View {
        HStack(spacing: 12) {
            Button(action: onOpenMusic) {
                HStack(spacing: 12) {
                    musicCover

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.playback.isPlaying ? "正在播放" : "音乐")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(WhaleTheme.accent)
                        Text(musicHeadline)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WhaleTheme.ink)
                            .lineLimit(1)
                        Text(musicSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WhaleTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开音乐，\\(musicHeadline)")

            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(WhaleTheme.accent, in: Circle())
                    .shadow(color: WhaleTheme.accent.opacity(0.35), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(model.playback.track == nil || model.isMusicBusy)
            .opacity(model.playback.track == nil ? 0.4 : 1)
            .accessibilityLabel(model.playback.isPlaying ? "暂停音乐" : "播放音乐")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [WhaleTheme.accent.opacity(0.12), WhaleTheme.card.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    private var musicCover: some View {
        ZStack {
            if let image = model.playback.track?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [WhaleTheme.moon.opacity(0.92), WhaleTheme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 9, height: 9)
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .offset(x: 13, y: -12)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    private var musicHeadline: String {
        model.playback.track?.title ?? "打开黑胶播放器"
    }

    private var musicSubtitle: String {
        guard let track = model.playback.track else {
            return "曲库 · \\(model.musicPlayMode.title) · 可导入本机文件"
        }
        if track.album.isEmpty || track.album == "本机文件" {
            return track.artist
        }
        return "\\(track.artist) · \\(track.album)"
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
                title: "今晚天气",
                subtitle: "温度·降雨·空气",
                icon: "cloud.sun.rain.fill",
                tint: WhaleTheme.coral,
                soft: WhaleTheme.amberSoft
            ) {
                send("查一下我所在地今晚到明天的天气。")
            }

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
        if todayEvents.isEmpty { return "今天先留一点空" }
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

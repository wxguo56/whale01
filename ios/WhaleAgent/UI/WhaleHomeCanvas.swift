import SwiftUI
import UIKit

/// The v9 home canvas. It is deliberately built from real model state:
/// calendar permission and events, recent operations and playback status.
struct WhaleHomeCanvas: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                quickGrid
                todayCard
                if let recent = model.recentActions.first {
                    recentCard(recent)
                }
                if model.isBusy {
                    busyCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28 + bottomInset)
        }
        .scrollIndicators(.hidden)
        .onTapGesture { dismissKeyboard() }
    }

    private var heroCard: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(WhaleTheme.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: WhaleTheme.accent, radius: 5)
                    Text("在听 · 也在做")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 16)

                Text("今天，\n交给我。")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(1)

                Text("说一句话，鲸鱼会找到答案，\n也会把事情办完。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .padding(.top, 9)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("写入前先确认")
                        .font(.system(size: 10, weight: .semibold))
                    if calendarGranted {
                        Text("·")
                        Text(todayStatusText)
                    }
                }
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)

            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 138, height: 126)
                .offset(x: 6, y: 8)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 210)
        .background {
            ZStack {
                WhaleTheme.heroGradient
                Circle()
                    .fill(WhaleTheme.accent.opacity(0.28))
                    .frame(width: 190, height: 190)
                    .blur(radius: 54)
                    .offset(x: 118, y: -88)
                Circle()
                    .fill(WhaleTheme.moon.opacity(0.17))
                    .frame(width: 150, height: 150)
                    .blur(radius: 44)
                    .offset(x: 110, y: 90)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: WhaleTheme.accent.opacity(0.16), radius: 24, y: 12)
    }

    private var quickGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            quickCard(
                title: "附近地点",
                subtitle: "距离 · 价格 · 营业",
                icon: "location.fill",
                tint: WhaleTheme.accent
            ) {
                send("找我附近两公里内的餐厅，按距离和价格帮我筛选。")
            }
            quickCard(
                title: "整理纪要",
                subtitle: "对话 · 待办 · 重点",
                icon: "text.badge.checkmark",
                tint: WhaleTheme.moon
            ) {
                send("帮我把今天的对话和任务整理成 3 条可执行待办。")
            }
            quickCard(
                title: "今晚天气",
                subtitle: "实时预报 · 带伞建议",
                icon: "cloud.sun.fill",
                tint: WhaleTheme.coral
            ) {
                send("查一下我所在地今晚到明天的天气。")
            }
            quickCard(
                title: model.playback.track == nil ? "我想听歌" : "继续听歌",
                subtitle: model.playback.track?.title ?? "本机音乐库",
                icon: model.playback.isPlaying ? "pause.fill" : "play.fill",
                tint: WhaleTheme.accentDeep
            ) {
                if model.playback.track != nil {
                    Task { await model.togglePlayback() }
                } else {
                    send("我想听歌。")
                }
            }
        }
    }

    private func quickCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.6))
                }

                Spacer(minLength: 14)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .padding(14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(WhaleTheme.card.opacity(0.72))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.08), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY · \(todayLabel)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(WhaleTheme.muted)
                    Text(calendarGranted ? todayTitle : "今天还没有读取日历")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
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

    private func recentCard(_ action: OperationRecord) -> some View {
        Button(action: onOpenRecords) {
            HStack(spacing: 12) {
                WhaleIconTile(
                    systemName: action.icon,
                    size: 42,
                    tint: action.isSuccess ? WhaleTheme.accent : WhaleTheme.coral
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("继续上次")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(WhaleTheme.muted)
                    Text(action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Text(action.isSuccess ? "已完成" : "待核对")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(action.isSuccess ? WhaleTheme.success : WhaleTheme.warm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
            }
            .whaleCard(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开任务与记录")
    }

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

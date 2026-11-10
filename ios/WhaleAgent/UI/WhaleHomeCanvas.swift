import SwiftUI
import UIKit

/// The conversation starter. Tapping 对话 lands here: a real chat surface with
/// a greeting, immediate prompts and the calendar state the phone actually has.
struct WhaleHomeCanvas: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                greeting
                suggestions
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

    // MARK: - Prompts

    private var suggestions: some View {
        WhaleFlowLayout(spacing: 8, lineSpacing: 8) {
            suggestion("附近找店", icon: "location.fill") {
                send("帮我找附近安静、适合两个人吃饭的地方，按距离和价格筛选。")
            }
            suggestion("今晚天气", icon: "cloud.sun.fill") {
                send("查一下我所在地今晚到明天的天气。")
            }
            suggestion("整理待办", icon: "checklist") {
                send("把今天的对话和任务整理成 3 条可执行待办。")
            }
            suggestion(
                model.playback.track == nil ? "我想听歌" : "继续听歌",
                icon: model.playback.isPlaying ? "pause.fill" : "music.note"
            ) {
                if model.playback.track != nil {
                    Task { await model.togglePlayback() }
                } else {
                    send("我想听歌。")
                }
            }
        }
    }

    private func suggestion(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
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

    // MARK: - Recent / busy

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
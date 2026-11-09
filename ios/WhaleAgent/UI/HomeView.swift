import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedTab: AppTab

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    quickActions
                    scheduleSection
                    permissionsSection
                    recentSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(WhaleTheme.background)
            .navigationTitle("鲸鱼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WhaleStatusPill(
                        text: model.backendOnline ? "服务在线" : "等待连接",
                        color: model.backendOnline ? .green : .orange
                    )
                }
            }
            .task {
                model.refreshPermissions()
                await model.refreshDashboard()
            }
            .refreshable {
                await model.health()
                model.refreshPermissions()
                await model.refreshDashboard(force: true)
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            WhaleTheme.heroGradient

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 190, height: 190)
                .offset(x: 240, y: -70)
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 110, height: 110)
                .offset(x: 270, y: 70)

            VStack(alignment: .leading, spacing: 12) {
                Label("你的 iPhone 助手", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Text("说一句，\n剩下交给鲸鱼。")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                Text("提醒、日程、地图、短信与音乐都在系统里完成。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    selectedTab = .chat
                } label: {
                    HStack(spacing: 8) {
                        Text("开始对话")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: WhaleTheme.accentDeep.opacity(0.18), radius: 20, y: 10)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhaleSectionTitle(title: "现在可以做")
            LazyVGrid(columns: columns, spacing: 12) {
                QuickActionCard(
                    title: "安排提醒",
                    subtitle: "写入系统提醒事项",
                    icon: "bell.badge.fill",
                    color: WhaleTheme.warm
                ) {
                    model.preparePrompt("明天下午三点提醒我取快递")
                    selectedTab = .chat
                }
                QuickActionCard(
                    title: "查看日程",
                    subtitle: "读取未来一周安排",
                    icon: "calendar",
                    color: .blue
                ) {
                    model.preparePrompt("帮我看看明天下午的安排")
                    selectedTab = .chat
                }
                QuickActionCard(
                    title: "附近地点",
                    subtitle: "搜索并交给系统地图",
                    icon: "map.fill",
                    color: .green
                ) {
                    model.preparePrompt("附近有哪家咖啡店？")
                    selectedTab = .chat
                }
                QuickActionCard(
                    title: "音乐",
                    subtitle: "打开真实音乐库",
                    icon: "music.note",
                    color: .purple
                ) {
                    selectedTab = .music
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhaleSectionTitle(title: "接下来的安排", action: "管理") {
                selectedTab = .settings
            }

            VStack(alignment: .leading, spacing: 12) {
                if model.permissionsSnapshot["calendarRead"] != "granted" {
                    PermissionCallout(
                        icon: "calendar.badge.plus",
                        title: "连接系统日历",
                        message: "授权后会在这里显示未来一周的真实日程。"
                    ) {
                        Task { await model.requestPermission("calendarRead") }
                    }
                } else if model.isDashboardLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取日历…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = model.dashboardError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if model.upcomingEvents.isEmpty {
                    Label("未来一周没有日程。", systemImage: "calendar.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.upcomingEvents) { event in
                        HStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text(WhaleDateText.shortDay(event.startAt))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(event.isAllDay ? "全天" : ToolPresentation.formatTime(event.startAt))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(width: 52)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                Text(event.calendarTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        if event.id != model.upcomingEvents.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .whaleCard()
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhaleSectionTitle(title: "系统权限", action: "全部") {
                selectedTab = .settings
            }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已授权 \(model.grantedPermissionCount) 项")
                            .font(.subheadline.weight(.semibold))
                        Text("只在你使用对应功能时读取数据。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(WhaleTheme.accent)
                }

                HStack(spacing: 8) {
                    PermissionMiniChip(name: "提醒", key: "reminder", model: model)
                    PermissionMiniChip(name: "日历", key: "calendarRead", model: model)
                    PermissionMiniChip(name: "音乐", key: "music", model: model)
                    PermissionMiniChip(name: "定位", key: "location", model: model)
                }
            }
            .whaleCard()
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WhaleSectionTitle(title: "最近执行")

            if model.recentActions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(WhaleTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(WhaleTheme.accent.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没有系统操作")
                            .font(.subheadline.weight(.medium))
                        Text("从上面的快捷入口开始，执行结果会留在这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .whaleCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.recentActions.prefix(4))) { action in
                        HStack(spacing: 12) {
                            Image(systemName: action.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(action.isSuccess ? WhaleTheme.accent : .orange)
                                .frame(width: 38, height: 38)
                                .background(
                                    (action.isSuccess ? WhaleTheme.accent : Color.orange).opacity(0.1),
                                    in: Circle()
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.title)
                                    .font(.subheadline.weight(.medium))
                                Text(action.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(action.createdAt, format: .dateTime.hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        if action.id != model.recentActions.prefix(4).last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .whaleCard(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionCallout: View {
    let icon: String
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(WhaleTheme.accent)
                .frame(width: 40, height: 40)
                .background(WhaleTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("允许", action: action)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(WhaleTheme.accent)
        }
    }
}

private struct PermissionMiniChip: View {
    let name: String
    let key: String
    @ObservedObject var model: AppModel

    var body: some View {
        let value = model.permissionsSnapshot[key] ?? "unknown"
        HStack(spacing: 4) {
            Circle()
                .fill(color(value))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color(value).opacity(0.09), in: Capsule())
    }

    private func color(_ value: String) -> Color {
        switch value {
        case "granted": return .green
        case "denied": return .red
        case "unavailable": return .gray
        default: return .orange
        }
    }
}

private enum WhaleDateText {
    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

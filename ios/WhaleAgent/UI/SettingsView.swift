import AVFoundation
import SwiftUI
import UIKit
import UserNotifications

private enum SettingsTone {
    case mint, blue, amber, rose

    var foreground: Color {
        switch self {
        case .mint: return WhaleTheme.accent
        case .blue: return WhaleTheme.moon
        case .amber: return WhaleTheme.warm
        case .rose: return WhaleTheme.rose
        }
    }

    var background: Color {
        switch self {
        case .mint: return WhaleTheme.accentSoft
        case .blue: return WhaleTheme.blueSoft
        case .amber: return WhaleTheme.amberSoft
        case .rose: return WhaleTheme.roseSoft
        }
    }
}

private struct SettingsRowSpec: Identifiable {
    let key: String
    let title: String
    let subtitle: String
    let icon: String
    let tone: SettingsTone

    var id: String { key }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var isDetailOpen: Bool
    var onBackToChat: () -> Void = {}

    @AppStorage("whale.appearance") private var appearance = "system"
    @State private var showDeveloper = false
    @State private var memoryKey = ""
    @State private var memoryValue = ""
    @State private var microphoneStatus = "unknown"
    @State private var notificationStatus = "unknown"

    private let primaryPermissions: [SettingsRowSpec] = [
        SettingsRowSpec(key: "location", title: "位置", subtitle: "精确位置 · 使用期间", icon: "location.fill", tone: .mint),
        SettingsRowSpec(key: "microphone", title: "麦克风", subtitle: "语音输入与播报", icon: "mic.fill", tone: .blue),
        SettingsRowSpec(key: "calendar", title: "日历", subtitle: "读取空闲时间 · 确认后写入", icon: "calendar", tone: .amber),
        SettingsRowSpec(key: "notifications", title: "通知", subtitle: "任务完成与主动提醒", icon: "bell.fill", tone: .rose)
    ]

    private let extraPermissions: [SettingsRowSpec] = [
        SettingsRowSpec(key: "reminder", title: "提醒事项", subtitle: "读取与写入待办", icon: "checklist", tone: .mint),
        SettingsRowSpec(key: "contacts", title: "通讯录", subtitle: "发送短信时查找联系人", icon: "person.2.fill", tone: .blue),
        SettingsRowSpec(key: "messages", title: "信息", subtitle: "生成短信草稿，不自动发送", icon: "message.fill", tone: .mint),
        SettingsRowSpec(key: "music", title: "音乐库", subtitle: "读取本机歌曲与播放状态", icon: "music.note", tone: .rose),
        SettingsRowSpec(key: "activityRead", title: "运动数据", subtitle: "读取步数与活动摘要", icon: "figure.walk", tone: .amber)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profileCard
                    permissionSection
                    preferenceSection
                    appearanceSection
                    memorySection
                    serviceSection
                    performanceSection
                    developerSection
                    versionCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, WhaleTabBar.height + 40)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDeveloper) {
                DeveloperSettingsView(model: model)
            }
            .onChange(of: showDeveloper) { _, open in
                isDetailOpen = open
            }
            .task {
                model.refreshPermissions()
                model.reloadMemories()
                refreshMicrophoneStatus()
                await refreshNotificationStatus()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CONTROL ROOM")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(WhaleTheme.muted)
                Text("设置")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
            }
            Spacer()
            Button(action: onBackToChat) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到对话")
        }
        .padding(.top, 10)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            WhaleMarkView(size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("本机账户")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("数据留在设备 · 授权后才读取")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 8)

            WhaleStatusPill(
                text: model.backendOnline ? "在线" : "离线",
                color: model.backendOnline ? WhaleTheme.success : WhaleTheme.warm
            )
        }
        .padding(15)
        .background(cardBackground)
    }

    // MARK: - Permissions

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("能力与授权", trailing: "来自系统真实状态")

            settingsCard {
                ForEach(Array(primaryPermissions.enumerated()), id: \.element.id) { index, spec in
                    PermissionSettingsRow(
                        spec: spec,
                        status: status(for: spec),
                        connectedLabel: spec.key == "calendar",
                        action: { handle(spec) }
                    )
                    if index < primaryPermissions.count - 1 {
                        rowDivider
                    }
                }
            }

            sectionHeader("更多能力", trailing: model.permissionsSnapshot.isEmpty ? nil : "同样读取系统状态")
                .padding(.top, 4)

            settingsCard {
                ForEach(Array(extraPermissions.enumerated()), id: \.element.id) { index, spec in
                    PermissionSettingsRow(
                        spec: spec,
                        status: status(for: spec),
                        connectedLabel: false,
                        action: { handle(spec) }
                    )
                    if index < extraPermissions.count - 1 {
                        rowDivider
                    }
                }
            }
        }
    }

    private func status(for spec: SettingsRowSpec) -> String {
        switch spec.key {
        case "microphone":
            return microphoneStatus
        case "notifications":
            return notificationStatus
        case "calendar":
            return model.permissionsSnapshot["calendarRead"] ?? "unknown"
        default:
            return model.permissionsSnapshot[spec.key] ?? "unknown"
        }
    }

    private func handle(_ spec: SettingsRowSpec) {
        let current = status(for: spec)
        if current == "granted" || current == "denied" || current == "unavailable" {
            openSystemSettings()
            return
        }
        switch spec.key {
        case "microphone":
            Task { await requestMicrophone() }
        case "notifications":
            Task { await requestNotifications() }
        case "calendar":
            Task { await model.requestPermission("calendarRead") }
        default:
            Task { await model.requestPermission(spec.key) }
        }
    }

    private func refreshMicrophoneStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphoneStatus = "granted"
        case .denied: microphoneStatus = "denied"
        case .undetermined: microphoneStatus = "unknown"
        @unknown default: microphoneStatus = "unknown"
        }
    }

    private func requestMicrophone() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphoneStatus = granted ? "granted" : "denied"
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "granted"
        case .denied:
            notificationStatus = "denied"
        case .notDetermined:
            notificationStatus = "unknown"
        @unknown default:
            notificationStatus = "unknown"
        }
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationStatus = granted ? "granted" : "denied"
        } catch {
            notificationStatus = "denied"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Preferences

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("助手偏好", trailing: "随时可改")

            settingsCard {
                Toggle(isOn: Binding(
                    get: { model.voiceReplyEnabled },
                    set: { model.setVoiceReply($0) }
                )) {
                    rowLabel(
                        title: "语音回应",
                        subtitle: "回答时同时播放语音",
                        icon: "mic.fill",
                        tone: .blue
                    )
                }
                .toggleStyle(.switch)
                .tint(WhaleTheme.accent)
                .frame(minHeight: 56)

                rowDivider

                HStack(spacing: 12) {
                    rowLabel(
                        title: "执行前确认",
                        subtitle: "写日历、发消息等操作必须先确认",
                        icon: "checkmark.shield.fill",
                        tone: .mint
                    )
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("始终开启")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(WhaleTheme.muted)
                }
                .frame(minHeight: 56)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("外观", trailing: "跟随当日光线")

            HStack(spacing: 9) {
                appearanceOption("深海", "深色", mode: "dark", swatch: .dark)
                appearanceOption("晨雾", "浅色", mode: "light", swatch: .light)
                appearanceOption("自动", "跟随系统", mode: "system", swatch: .auto)
            }
        }
    }

    private enum AppearanceSwatch {
        case dark, light, auto
    }

    private func appearanceOption(
        _ title: String,
        _ subtitle: String,
        mode: String,
        swatch: AppearanceSwatch
    ) -> some View {
        let selected = appearance == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appearance = mode
            }
        } label: {
            VStack(spacing: 7) {
                swatchPreview(swatch)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(WhaleTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        selected ? WhaleTheme.accent : WhaleTheme.line,
                        lineWidth: selected ? 1.5 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)外观")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func swatchPreview(_ swatch: AppearanceSwatch) -> some View {
        ZStack {
            switch swatch {
            case .dark:
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.12, blue: 0.14), Color(red: 0.07, green: 0.23, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.98, blue: 0.97), .white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .auto:
                HStack(spacing: 0) {
                    Color(red: 0.05, green: 0.15, blue: 0.17)
                    Color(red: 0.97, green: 0.99, blue: 0.98)
                }
            }

            VStack(spacing: 4) {
                Capsule().fill(WhaleTheme.accent.opacity(0.8)).frame(width: 24, height: 3)
                Capsule().fill(WhaleTheme.muted.opacity(0.35)).frame(width: 34, height: 3)
                Capsule().fill(WhaleTheme.muted.opacity(0.22)).frame(width: 18, height: 3)
            }
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("记忆偏好", trailing: "只影响建议")

            settingsCard {
                if model.memories.isEmpty {
                    Text("还没有保存偏好。可以记住饮食、音乐、回复风格；偏好只影响建议，不会变成长期操作授权。")
                        .font(.system(size: 12))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(model.memories) { preference in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preference.key)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WhaleTheme.ink)
                                Text(preference.value)
                                    .font(.system(size: 12))
                                    .foregroundStyle(WhaleTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button {
                                model.deleteMemory(preference)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WhaleTheme.danger)
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除偏好 \(preference.key)")
                        }
                        .frame(minHeight: 44)
                        rowDivider
                    }
                }

                VStack(spacing: 8) {
                    TextField("偏好名称，例如：饮食", text: $memoryKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(WhaleTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 8) {
                        TextField("内容，例如：不吃辣", text: $memoryValue)
                            .font(.system(size: 13))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(WhaleTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button("保存") {
                            model.addMemory(key: memoryKey, value: memoryValue)
                            memoryKey = ""
                            memoryValue = ""
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .tint(WhaleTheme.accent)
                        .disabled(memoryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || memoryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Services

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("服务连接", trailing: "只显示真实接入")

            settingsCard {
                serviceRow(
                    title: "DeepSeek",
                    subtitle: model.agentMode == "cloud"
                        ? "云后端 · \(model.modelMode)"
                        : "本机直连 · \(model.modelMode)",
                    badge: "D",
                    badgeIcon: nil,
                    badgeTone: .blue,
                    connected: deepSeekConnected
                )

                rowDivider

                serviceRow(
                    title: "讯飞语音",
                    subtitle: XfyunConfig.statusText,
                    badge: "讯",
                    badgeIcon: nil,
                    badgeTone: .mint,
                    connected: XfyunConfig.isConfigured
                )

                rowDivider

                serviceRow(
                    title: "网络",
                    subtitle: model.agentMode == "cloud"
                        ? "公网后端 · 不依赖局域网"
                        : "本机直连 · 无需电脑中转",
                    badge: "",
                    badgeIcon: "globe",
                    badgeTone: .blue,
                    connected: networkConnected
                )
            }
        }
    }

    private var deepSeekConnected: Bool {
        model.agentMode == "cloud" ? model.backendOnline : LocalAgentConfig.isConfigured
    }

    private var networkConnected: Bool {
        model.agentMode == "cloud" ? model.backendOnline : LocalAgentConfig.isConfigured
    }

    private func serviceRow(
        title: String,
        subtitle: String,
        badge: String,
        badgeIcon: String?,
        badgeTone: SettingsTone,
        connected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Group {
                if let badgeIcon {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text(badge)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(badgeTone.foreground)
            .frame(width: 38, height: 38)
            .background(badgeTone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusPill(
                text: connected ? "已连接" : "未配置",
                color: connected ? WhaleTheme.success : WhaleTheme.muted
            )
        }
        .frame(minHeight: 56)
    }

    // MARK: - Performance / developer

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("性能", trailing: "本机测量")

            settingsCard {
                infoRow("首轮响应", TurnMetricsStore.summary)
                rowDivider
                infoRow("设备操作", ToolMetricsStore.summary)
                Text("分别记录模型首轮响应与设备执行耗时，不含用户确认等待。")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("维护", trailing: nil)

            settingsCard {
                Button {
                    showDeveloper = true
                } label: {
                    HStack(spacing: 12) {
                        rowLabel(
                            title: "开发设置与诊断",
                            subtitle: "运行方式、连接状态与权限快照",
                            icon: "hammer.fill",
                            tone: .amber
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WhaleTheme.muted)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var versionCard: some View {
        HStack(spacing: 10) {
            WhaleMarkView(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("WhaleAgent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("\(model.versionText) · UI v9")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 8)

            Text("本机构建")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(WhaleTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(WhaleTheme.accentSoft, in: Capsule())
        }
        .padding(13)
        .background(cardBackground)
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WhaleTheme.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
            }
        }
        .padding(.horizontal, 3)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(WhaleTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(WhaleTheme.line.opacity(0.9), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
    }

    private func rowLabel(title: String, subtitle: String, icon: String, tone: SettingsTone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .frame(width: 38, height: 38)
                .background(tone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(2)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(WhaleTheme.line.opacity(0.7))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Rows

private struct PermissionSettingsRow: View {
    let spec: SettingsRowSpec
    let status: String
    let connectedLabel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: spec.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(spec.tone.foreground)
                    .frame(width: 38, height: 38)
                    .background(spec.tone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                    Text(spec.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                StatusPill(text: statusText, color: statusColor)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted.opacity(0.55))
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(spec.title)，\(statusText)")
    }

    private var statusText: String {
        switch status {
        case "granted": return connectedLabel ? "已连接" : "已授权"
        case "denied": return "已拒绝"
        case "unavailable": return "不可用"
        default: return "未开启"
        }
    }

    private var statusColor: Color {
        switch status {
        case "granted": return WhaleTheme.success
        case "denied": return WhaleTheme.danger
        case "unavailable": return WhaleTheme.muted
        default: return WhaleTheme.muted
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Developer

struct DeveloperSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("运行方式") {
                Picker("Agent", selection: $model.agentMode) {
                    Text("本机直连").tag("local")
                    Text("云后端").tag("cloud")
                }
                .onChange(of: model.agentMode) { _, _ in
                    model.saveAgentMode()
                }
                LabeledContent("状态", value: model.statusLine)
                if model.agentMode != "cloud" {
                    LabeledContent("本机密钥", value: LocalAgentConfig.isConfigured ? "已配置" : "缺失")
                }
            }

            if model.agentMode == "cloud" {
                Section("后端服务") {
                    TextField("https://your-backend.example.com", text: $model.backendURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("保存并检查") {
                        model.saveBackendURL()
                    }
                    LabeledContent("连接状态", value: model.statusLine)
                    if let checked = model.lastCheckedAt {
                        LabeledContent("最近检查", value: checked.formatted(date: .abbreviated, time: .standard))
                    }
                }
            }

            Section("连接诊断") {
                LabeledContent("模型", value: model.modelMode)
                LabeledContent("执行模式", value: model.backendExecutionMode)
                LabeledContent("工具数量", value: "\(model.toolCount)")
                LabeledContent("鉴权", value: model.authRequired ? "已开启" : "未开启")
                LabeledContent("构建", value: model.versionText)
                LabeledContent("Bundle ID", value: model.bundleIdentifier)
                Button("重新检查服务") {
                    Task { await model.health() }
                }
            }

            Section("权限快照") {
                ForEach(model.permissionsSnapshot.keys.sorted(), id: \.self) { key in
                    LabeledContent(PermissionCenter.label(key), value: model.permissionsSnapshot[key] ?? "unknown")
                }
                Button("刷新权限") {
                    model.refreshPermissions()
                }
            }

            Section("说明") {
                Text("本机直连模式把 DeepSeek 密钥编译进安装包，只适合个人设备；云后端模式把密钥留在服务器。切换后会自动重新检查。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开发设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
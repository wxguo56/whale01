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


fileprivate enum SettingsChrome {
    static func header(_ title: String, trailing: String?) -> some View {
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

    static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(cardBackground)
    }

    static var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(WhaleTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(WhaleTheme.line.opacity(0.9), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
    }

    static func label(title: String, subtitle: String, icon: String, tone: SettingsTone) -> some View {
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

    static var divider: some View {
        Rectangle()
            .fill(WhaleTheme.line.opacity(0.7))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    static func infoRow(_ title: String, _ value: String) -> some View {
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

fileprivate enum PermissionCatalog {
    static let primary: [SettingsRowSpec] = [
        SettingsRowSpec(key: "location", title: "位置", subtitle: "精确位置 · 使用期间", icon: "location.fill", tone: .mint),
        SettingsRowSpec(key: "microphone", title: "麦克风", subtitle: "语音输入与播报", icon: "mic.fill", tone: .blue),
        SettingsRowSpec(key: "calendar", title: "日历", subtitle: "读取空闲时间 · 确认后写入", icon: "calendar", tone: .amber),
        SettingsRowSpec(key: "notifications", title: "通知", subtitle: "任务完成与主动提醒", icon: "bell.fill", tone: .rose)
    ]

    static let extra: [SettingsRowSpec] = [
        SettingsRowSpec(key: "reminder", title: "提醒事项", subtitle: "读取与写入待办", icon: "checklist", tone: .mint),
        SettingsRowSpec(key: "contacts", title: "通讯录", subtitle: "发送短信时查找联系人", icon: "person.2.fill", tone: .blue),
        SettingsRowSpec(key: "messages", title: "信息", subtitle: "生成短信草稿，不自动发送", icon: "message.fill", tone: .mint),
        SettingsRowSpec(key: "music", title: "音乐库", subtitle: "读取本机歌曲与播放状态", icon: "music.note", tone: .rose),
        SettingsRowSpec(key: "activityRead", title: "运动数据", subtitle: "读取步数与活动摘要", icon: "figure.walk", tone: .amber)
    ]

    static let all: [SettingsRowSpec] = primary + extra
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var isDetailOpen: Bool
    var onBackToChat: () -> Void = {}

    @AppStorage("whale.appearance") private var appearance = "system"
    @AppStorage("whale.profile.nickname") private var profileNickname = ""
    @AppStorage("whale.profile.bio") private var profileBio = ""
    @State private var showProfileEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    profileCard
                    appearanceSection
                    categorySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, WhaleTabBar.height + 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { hideKeyboard() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorSheet(model: model)
            }
            .task {
                model.refreshPermissions()
                model.reloadMemories()
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

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
        Button {
            showProfileEditor = true
        } label: {
            HStack(spacing: 12) {
                WhaleMarkView(size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profileNickname.isEmpty ? "个人资料" : profileNickname)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(1)
                    Text(profileBio.isEmpty ? "填写昵称和介绍，鲸鱼会更懂你" : profileBio)
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 7) {
                    WhaleStatusPill(
                        text: model.backendOnline ? "在线" : "离线",
                        color: model.backendOnline ? WhaleTheme.success : WhaleTheme.warm
                    )
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.7))
                }
            }
            .padding(15)
            .background(SettingsChrome.cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑个人资料")
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsChrome.header("分类", trailing: "点开查看细节")

            SettingsChrome.card {
                categoryLink(
                    title: "能力与授权",
                    subtitle: "麦克风、日历、通知等 \(PermissionCatalog.all.count) 项",
                    icon: "checkmark.shield.fill",
                    tone: .mint
                ) { PermissionsSettingsView(model: model) }

                SettingsChrome.divider

                categoryLink(
                    title: "助手偏好",
                    subtitle: model.voiceReplyEnabled ? "语音回应已开启" : "语音回应已关闭",
                    icon: "slider.horizontal.3",
                    tone: .blue
                ) { PreferencesSettingsView(model: model) }

                SettingsChrome.divider

                categoryLink(
                    title: "记忆偏好",
                    subtitle: model.memories.isEmpty ? "还没有保存偏好" : "已保存 \(model.memories.count) 条",
                    icon: "brain.head.profile",
                    tone: .amber
                ) { MemorySettingsView(model: model) }

                SettingsChrome.divider

                categoryLink(
                    title: "服务连接",
                    subtitle: model.agentMode == "cloud" ? "云后端 · \(model.modelMode)" : "本机直连 · \(model.modelMode)",
                    icon: "antenna.radiowaves.left.and.right",
                    tone: .blue
                ) { ServiceSettingsView(model: model) }

                SettingsChrome.divider

                categoryLink(
                    title: "性能与诊断",
                    subtitle: "响应耗时、开发设置与版本",
                    icon: "speedometer",
                    tone: .rose
                ) { AdvancedSettingsView(model: model, isDetailOpen: $isDetailOpen) }
            }
        }
    }

    private func categoryLink<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tone: SettingsTone,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .onAppear { isDetailOpen = true }
                .onDisappear { isDetailOpen = false }
        } label: {
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
                        .lineLimit(1)
                }

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

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsChrome.header("外观", trailing: "跟随当日光线")

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
}

// MARK: - Category destinations

private struct PermissionsSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var microphoneStatus = "unknown"
    @State private var notificationStatus = "unknown"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsChrome.header("系统权限", trailing: "来自系统真实状态")

                SettingsChrome.card {
                    ForEach(Array(PermissionCatalog.primary.enumerated()), id: \.element.id) { index, spec in
                        PermissionSettingsRow(
                            spec: spec,
                            status: status(for: spec),
                            connectedLabel: spec.key == "calendar",
                            action: { handle(spec) }
                        )
                        if index < PermissionCatalog.primary.count - 1 {
                            SettingsChrome.divider
                        }
                    }
                }

                SettingsChrome.header("更多能力", trailing: nil)

                SettingsChrome.card {
                    ForEach(Array(PermissionCatalog.extra.enumerated()), id: \.element.id) { index, spec in
                        PermissionSettingsRow(
                            spec: spec,
                            status: status(for: spec),
                            connectedLabel: false,
                            action: { handle(spec) }
                        )
                        if index < PermissionCatalog.extra.count - 1 {
                            SettingsChrome.divider
                        }
                    }
                }

                Text("授权状态由系统决定；被拒绝的项目需要到系统设置里重新开启。")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .padding(.horizontal, 3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(WhaleBackdrop())
        .scrollIndicators(.hidden)
        .navigationTitle("能力与授权")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.refreshPermissions()
            refreshMicrophoneStatus()
            await refreshNotificationStatus()
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
}

private struct PreferencesSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsChrome.header("助手偏好", trailing: "随时可改")

                SettingsChrome.card {
                    Toggle(isOn: Binding(
                        get: { model.voiceReplyEnabled },
                        set: { model.setVoiceReply($0) }
                    )) {
                        SettingsChrome.label(
                            title: "语音回应",
                            subtitle: "回答时同时播放语音",
                            icon: "mic.fill",
                            tone: .blue
                        )
                    }
                    .toggleStyle(.switch)
                    .tint(WhaleTheme.accent)
                    .frame(minHeight: 56)

                    SettingsChrome.divider

                    HStack(spacing: 12) {
                        SettingsChrome.label(
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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(WhaleBackdrop())
        .scrollIndicators(.hidden)
        .navigationTitle("助手偏好")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MemorySettingsView: View {
    @ObservedObject var model: AppModel
    @State private var memoryKey = ""
    @State private var memoryValue = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsChrome.header("记忆偏好", trailing: "只影响建议")

                SettingsChrome.card {
                    if model.memories.isEmpty {
                        Text("还没有保存偏好。可以记住饮食、音乐、回复风格；偏好只影响建议，不会变成长期操作授权。")
                            .font(.system(size: 12))
                            .foregroundStyle(WhaleTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
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
                            SettingsChrome.divider
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
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(WhaleBackdrop())
        .scrollIndicators(.hidden)
        .navigationTitle("记忆偏好")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ServiceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsChrome.header("服务连接", trailing: "只显示真实接入")

                SettingsChrome.card {
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

                    SettingsChrome.divider

                    serviceRow(
                        title: "讯飞语音",
                        subtitle: XfyunConfig.statusText,
                        badge: "讯",
                        badgeIcon: nil,
                        badgeTone: .mint,
                        connected: XfyunConfig.isConfigured
                    )

                    SettingsChrome.divider

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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(WhaleBackdrop())
        .scrollIndicators(.hidden)
        .navigationTitle("服务连接")
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct AdvancedSettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var isDetailOpen: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsChrome.header("性能", trailing: "本机测量")

                SettingsChrome.card {
                    SettingsChrome.infoRow("首轮响应", TurnMetricsStore.summary)
                    SettingsChrome.divider
                    SettingsChrome.infoRow("设备操作", ToolMetricsStore.summary)
                    Text("分别记录模型首轮响应与设备执行耗时，不含用户确认等待。")
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }

                SettingsChrome.header("维护", trailing: nil)

                SettingsChrome.card {
                    NavigationLink {
                        DeveloperSettingsView(model: model)
                            .onAppear { isDetailOpen = true }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsChrome.label(
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

                SettingsChrome.header("关于", trailing: nil)

                SettingsChrome.card {
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
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(WhaleBackdrop())
        .scrollIndicators(.hidden)
        .navigationTitle("性能与诊断")
        .navigationBarTitleDisplayMode(.inline)
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
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("开发设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileEditorSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("whale.profile.nickname") private var storedNickname = ""
    @AppStorage("whale.profile.bio") private var storedBio = ""

    @State private var nickname = ""
    @State private var bio = ""
    @FocusState private var focusedField: Field?

    private enum Field { case nickname, bio }
    private let nicknameLimit = 20
    private let bioLimit = 80

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    form
                    note
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(WhaleBackdrop())
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .onAppear {
                nickname = storedNickname
                bio = storedBio
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var identity: some View {
        HStack(spacing: 14) {
            WhaleMarkView(size: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text("资料保存在这台设备，对话时作为上下文使用")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .whaleCard(padding: 16)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldHeader("昵称", count: nickname.count, limit: nicknameLimit)

            TextField("鲸鱼怎么称呼你", text: $nickname)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .nickname)
                .submitLabel(.next)
                .onSubmit { focusedField = .bio }
                .onChange(of: nickname) { _, value in
                    if value.count > nicknameLimit {
                        nickname = String(value.prefix(nicknameLimit))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    WhaleTheme.field,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WhaleTheme.line.opacity(0.8), lineWidth: 0.7)
                }

            Divider()
                .overlay(WhaleTheme.line.opacity(0.7))
                .padding(.vertical, 2)

            fieldHeader("自我介绍", count: bio.count, limit: bioLimit)

            TextField("例如：喜欢安静的小店，常在上海", text: $bio, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(3...5)
                .focused($focusedField, equals: .bio)
                .submitLabel(.done)
                .onChange(of: bio) { _, value in
                    if value.count > bioLimit {
                        bio = String(value.prefix(bioLimit))
                    }
                }
                .padding(12)
                .background(
                    WhaleTheme.field,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WhaleTheme.line.opacity(0.8), lineWidth: 0.7)
                }
        }
        .whaleCard(padding: 16)
    }

    private var note: some View {
        Label(
            "昵称和自我介绍会同步到「记忆偏好」，用于称呼和对话理解；只保存在本机，对话时会作为上下文发送给鲸鱼模型。",
            systemImage: "lock.shield"
        )
        .font(.system(size: 11))
        .foregroundStyle(WhaleTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 2)
    }

    private var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未设置昵称" : trimmed
    }

    private func fieldHeader(_ title: String, count: Int, limit: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Spacer()
            Text("\(count)/\(limit)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(count >= limit ? WhaleTheme.coral : WhaleTheme.muted)
        }
    }

    private func save() {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        storedNickname = name
        storedBio = intro
        model.syncProfile(nickname: name, bio: intro)
        dismiss()
    }
}

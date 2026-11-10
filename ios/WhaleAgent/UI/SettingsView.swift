import SwiftUI

private struct PermissionRowSpec: Identifiable {
    let key: String
    let title: String
    let icon: String

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

    private let permissionRows: [PermissionRowSpec] = [
        PermissionRowSpec(key: "reminder", title: "提醒事项", icon: "bell.badge"),
        PermissionRowSpec(key: "calendarRead", title: "日历读取", icon: "calendar"),
        PermissionRowSpec(key: "calendarWrite", title: "日历写入", icon: "calendar.badge.plus"),
        PermissionRowSpec(key: "location", title: "定位", icon: "location"),
        PermissionRowSpec(key: "contacts", title: "通讯录", icon: "person.2"),
        PermissionRowSpec(key: "messages", title: "信息", icon: "message"),
        PermissionRowSpec(key: "music", title: "音乐库", icon: "music.note"),
        PermissionRowSpec(key: "activityRead", title: "运动数据", icon: "figure.walk")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    identityCard
                    appearanceCard
                    voiceCard
                    memoryCard
                    permissionCard
                    performanceCard
                    developerCard
                    aboutCard
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.bottom, 28)
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
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text("偏好、授权与语音")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
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
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(WhaleTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("鲸鱼")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("版本 \(model.versionText)")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
            WhaleStatusPill(
                text: model.backendOnline ? "在线" : "离线",
                color: model.backendOnline ? WhaleTheme.success : WhaleTheme.warm
            )
        }
        .whaleCard()
    }

    private var appearanceCard: some View {
        card("外观") {
            Picker("界面主题", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var voiceCard: some View {
        card("语音") {
            Toggle("自动播报回复", isOn: Binding(
                get: { model.voiceReplyEnabled },
                set: { model.setVoiceReply($0) }
            ))
            .tint(WhaleTheme.accent)
            .font(.system(size: 15))
            .foregroundStyle(WhaleTheme.ink)

            divider
            infoRow("播报引擎", "系统中文语音")
            divider
            infoRow("语音识别", XfyunConfig.statusText)

            Text("开始录音、发送新消息或点消息旁的停止按钮会立刻打断播报。讯飞合成尚未接入，当前播报使用系统中文语音。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionCard: some View {
        card("系统权限") {
            ForEach(Array(permissionRows.enumerated()), id: \.element.id) { index, row in
                PermissionSettingsRow(
                    key: row.key,
                    title: row.title,
                    icon: row.icon,
                    status: model.permissionsSnapshot[row.key] ?? "unknown",
                    onRequest: { Task { await model.requestPermission(row.key) } },
                    onOpenSettings: { model.openSystemSettings() }
                )
                if index < permissionRows.count - 1 {
                    divider
                }
            }
            Button {
                model.refreshPermissions()
            } label: {
                Text("刷新权限状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var memoryCard: some View {
        card("记忆偏好") {
            if model.memories.isEmpty {
                Text("还没有保存偏好。可以记住饮食、音乐、回复风格等；偏好只影响建议，不会变成长期操作授权。")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                    divider
                }
            }

            VStack(spacing: 8) {
                TextField("偏好名称，例如：饮食", text: $memoryKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 8) {
                    TextField("内容，例如：不吃辣", text: $memoryValue)
                        .font(.system(size: 13))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var performanceCard: some View {
        card("性能") {
            infoRow("首轮响应", TurnMetricsStore.summary)
            divider
            infoRow("设备操作", ToolMetricsStore.summary)
            Text("分别记录模型首轮响应与设备执行耗时，不含用户确认等待；完整测量见 Beta 测试报告。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var developerCard: some View {
        card("开发") {
            Button {
                showDeveloper = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hammer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WhaleTheme.accent)
                    Text("开发设置与诊断")
                        .font(.system(size: 15))
                        .foregroundStyle(WhaleTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        card("关于") {
            infoRow("应用", "鲸鱼")
            divider
            infoRow("版本", model.versionText)
            divider
            infoRow("隐私", "对话经 DeepSeek 处理，系统数据留在设备")
            Text("鲸鱼只在获得确认后写入提醒、日历和短信草稿；天气与运动摘要需要对应系统能力授权。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whaleCard()
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
        .frame(minHeight: 24)
    }

    private var divider: some View {
        Divider().overlay(WhaleTheme.glassStroke)
    }
}

private struct PermissionSettingsRow: View {
    let key: String
    let title: String
    let icon: String
    let status: String
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhaleTheme.accent)
                .frame(width: 30, height: 30)
                .background(WhaleTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(WhaleTheme.ink)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            switch status {
            case "granted":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(WhaleTheme.success)
            case "denied":
                Button("设置", action: onOpenSettings)
                    .font(.system(size: 12, weight: .semibold))
                    .tint(WhaleTheme.accent)
            case "unavailable":
                Text("不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
            default:
                Button("授权", action: onRequest)
                    .font(.system(size: 12, weight: .semibold))
                    .tint(WhaleTheme.accent)
            }
        }
        .frame(minHeight: 42)
    }

    private var statusText: String {
        switch status {
        case "granted": return "已授权"
        case "denied": return "已拒绝 · 可在系统设置中修改"
        case "unavailable": return "当前构建不可用"
        default: return "尚未请求"
        }
    }

    private var statusColor: Color {
        switch status {
        case "granted": return WhaleTheme.success
        case "denied": return WhaleTheme.danger
        case "unavailable": return WhaleTheme.muted
        default: return WhaleTheme.warm
        }
    }
}

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

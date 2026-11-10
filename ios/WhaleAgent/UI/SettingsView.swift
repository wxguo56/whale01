import SwiftUI

private struct PermissionRowSpec: Identifiable {
    let key: String
    let title: String
    let icon: String

    var id: String { key }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

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
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(WhaleTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("鲸鱼")
                                .font(.title2.weight(.bold))
                            Text("版本 \(model.versionText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        WhaleStatusPill(
                            text: model.backendOnline ? "在线" : "离线",
                            color: model.backendOnline ? .green : .orange
                        )
                    }
                    .padding(.vertical, 6)
                }

                Section("系统权限") {
                    ForEach(permissionRows) { row in
                        PermissionSettingsRow(
                            key: row.key,
                            title: row.title,
                            icon: row.icon,
                            status: model.permissionsSnapshot[row.key] ?? "unknown",
                            onRequest: { Task { await model.requestPermission(row.key) } },
                            onOpenSettings: { model.openSystemSettings() }
                        )
                    }
                    Button("刷新权限状态") {
                        model.refreshPermissions()
                    }
                    .font(.subheadline.weight(.medium))
                }

                Section("性能") {
                    LabeledContent("首轮响应", value: TurnMetricsStore.summary)
                    LabeledContent("设备操作", value: ToolMetricsStore.summary)
                    Text("分别记录模型首轮响应与设备执行耗时，不含用户确认等待；完整测量见 Beta 测试报告。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("语音") {
                    Toggle("自动播报回复", isOn: Binding(
                        get: { model.voiceReplyEnabled },
                        set: { model.setVoiceReply($0) }
                    ))
                    LabeledContent("播报引擎", value: "系统中文语音")
                    LabeledContent("语音引擎", value: XfyunConfig.statusText)
                    Text("语音对话的回复会自动播报；开始录音、发送新消息或点消息旁的停止按钮会立刻打断。讯飞合成尚未接入，当前播报使用系统中文语音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("开发") {
                    NavigationLink {
                        DeveloperSettingsView(model: model)
                    } label: {
                        Label("开发设置与诊断", systemImage: "hammer")
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "鲸鱼")
                    LabeledContent("版本", value: model.versionText)
                    LabeledContent("隐私", value: "对话经 DeepSeek 处理，系统数据留在设备")
                    Text("鲸鱼只在获得确认后写入提醒、日历和短信草稿；天气与运动摘要需要对应系统能力授权。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(WhaleTheme.background)
            .navigationTitle("设置")
            .task { model.refreshPermissions() }
        }
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhaleTheme.accent)
                .frame(width: 30, height: 30)
                .background(WhaleTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            switch status {
            case "granted":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case "denied":
                Button("设置", action: onOpenSettings)
                    .font(.caption.weight(.semibold))
            case "unavailable":
                Text("不可用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            default:
                Button("授权", action: onRequest)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 2)
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
        case "granted": return .green
        case "denied": return .red
        case "unavailable": return .secondary
        default: return .orange
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

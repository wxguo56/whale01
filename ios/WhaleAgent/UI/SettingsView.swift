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
                    LabeledContent("隐私", value: "数据留在设备与你的后端")
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

private struct DeveloperSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("后端服务") {
                TextField("http://192.168.x.x:8787", text: $model.backendURL)
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

            Section("连接诊断") {
                LabeledContent("模型", value: model.modelMode)
                LabeledContent("执行模式", value: model.backendExecutionMode)
                LabeledContent("工具数量", value: "\(model.toolCount)")
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
                Text("这里只用于开发和真机诊断。DeepSeek 密钥保存在后端，不会写入 App，也不会显示在客户端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开发设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

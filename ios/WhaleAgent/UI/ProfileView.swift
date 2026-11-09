import SwiftUI

struct ProfileView: View {
    @ObservedObject var model: AppModel
    @AppStorage("whale.appearance") private var appearance = "system"

    private let permissions: [(key: String, title: String, icon: String)] = [
        ("reminder", "提醒事项", "bell.badge"),
        ("calendarRead", "日历读取", "calendar"),
        ("location", "定位", "location"),
        ("contacts", "通讯录", "person.2"),
        ("music", "系统音乐库", "music.note")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileHeader
                    preferences
                    appearanceCard
                    permissionCard
                    serviceCard
                    aboutCard
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(WhaleTheme.background)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .task { model.refreshPermissions() }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 15) {
            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 56)
                .padding(6)
                .background(WhaleTheme.soft, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("鲸鱼01")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("版本 \(model.versionText) · \(model.backendOnline ? "服务在线" : "服务未连接")")
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("偏好记忆")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("还没有保存偏好。对鲸鱼说「记住我不吃辣」这类要求，保存后会显示在这里。")
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(WhaleTheme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("界面主题")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Picker("界面主题", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
        }
        .whaleCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("授权")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
                .padding(.bottom, 6)
            ForEach(Array(permissions.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 11) {
                    Image(systemName: row.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 22)
                    Text(row.title)
                        .font(.system(size: 15))
                        .foregroundStyle(WhaleTheme.ink)
                    Spacer()
                    permissionControl(for: row.key)
                }
                .frame(minHeight: 48)
                if index < permissions.count - 1 {
                    Divider().overlay(WhaleTheme.line)
                }
            }
        }
        .whaleCard()
    }

    @ViewBuilder
    private func permissionControl(for key: String) -> some View {
        let status = model.permissionsSnapshot[key] ?? "unknown"
        switch status {
        case "granted":
            Label("已授权", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WhaleTheme.success)
        case "denied":
            Button("去设置") { model.openSystemSettings() }
                .font(.system(size: 12, weight: .semibold))
                .tint(WhaleTheme.accent)
        case "unavailable":
            Text("不可用")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
        default:
            Button("授权") { Task { await model.requestPermission(key) } }
                .font(.system(size: 12, weight: .semibold))
                .tint(WhaleTheme.accent)
        }
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("服务")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            HStack(spacing: 8) {
                Circle()
                    .fill(model.backendOnline ? WhaleTheme.success : WhaleTheme.warm)
                    .frame(width: 7, height: 7)
                Text(model.statusLine)
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
                Spacer()
            }
            SecureField("后端访问码", text: $model.apiToken)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(WhaleTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                model.saveAPIToken()
            } label: {
                Text("保存访问码")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .foregroundStyle(WhaleTheme.accent)
            .background(WhaleTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            NavigationLink {
                DeveloperSettingsView(model: model)
            } label: {
                HStack {
                    Text("开发设置")
                        .font(.system(size: 15))
                        .foregroundStyle(WhaleTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                }
                .frame(minHeight: 44)
            }
        }
        .whaleCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("数据留在设备与你的后端。鲸鱼只在获得确认后写入提醒、日历和短信草稿；导入的音乐只保存在 App 沙盒。")
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whaleCard()
    }
}

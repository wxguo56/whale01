import SwiftUI

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                Divider()
                conversation
                Divider()
                inputBar
            }
            .navigationTitle("鲸鱼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
        }
        .task {
            await model.health()
            model.refreshPermissions()
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.teal)
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.permissionsSnapshot.keys.sorted(), id: \.self) { key in
                        PermissionChip(key: key, value: model.permissionsSnapshot[key] ?? "unknown")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    ForEach(model.pending) { item in
                        PendingToolCard(
                            item: item,
                            isBusy: model.isBusy,
                            onConfirm: { Task { await model.confirm(item) } },
                            onSkip: { Task { await model.skip(item) } }
                        )
                        .id(item.id)
                    }
                    if let error = model.errorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .onChange(of: model.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.pending.count) {
                scrollToBottom(proxy)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("说点什么，例如：明天下午三点提醒我取快递", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
                .onSubmit {
                    Task { await model.send() }
                }
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(model.isBusy || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = model.pending.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else if let last = model.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(background, in: RoundedRectangle(cornerRadius: 14))
            if message.role != .user { Spacer(minLength: 36) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: return Color.teal.opacity(0.18)
        case .assistant: return Color.gray.opacity(0.14)
        case .tool: return Color.orange.opacity(0.14)
        }
    }
}

private struct PendingToolCard: View {
    let item: PendingTool
    let isBusy: Bool
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "iphone")
                Text(ToolCatalog.label(item.tool))
                    .font(.headline)
                Spacer()
                Text(item.requiresConfirmation ? "需确认" : "自动执行")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Text(ToolCatalog.summary(item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if item.requiresConfirmation {
                HStack {
                    Button("执行", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    Button("跳过", role: .destructive, action: onSkip)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在 iPhone 上执行…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PermissionChip: View {
    let key: String
    let value: String

    var body: some View {
        let color = chipColor
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(PermissionCenter.label(key)) \(valueText)")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var chipColor: Color {
        switch value {
        case "granted": return .green
        case "denied": return .red
        default: return .orange
        }
    }

    private var valueText: String {
        switch value {
        case "granted": return "已授权"
        case "denied": return "已拒绝"
        case "unavailable": return "免费签名不可用"
        default: return "未请求"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("后端") {
                    TextField("http://192.168.x.x:8787", text: $model.backendURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存并检查") {
                        model.saveBackendURL()
                    }
                }
                Section("权限") {
                    ForEach(model.permissionsSnapshot.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(PermissionCenter.label(key))
                            Spacer()
                            Text(model.permissionsSnapshot[key] ?? "unknown")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("刷新权限") {
                        model.refreshPermissions()
                    }
                }
                Section("说明") {
                    Text("DeepSeek 密钥只保存在后端，不会写入 App。真机执行需要后端以 EXECUTION_MODE=ios 启动。")
                        .font(.caption)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

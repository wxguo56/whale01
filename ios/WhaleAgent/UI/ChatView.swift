import SwiftUI

struct ChatView: View {
    @ObservedObject var model: AppModel
    @StateObject private var voice = VoiceInputController()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.backendOnline || model.errorText != nil {
                    connectionBanner
                }
                conversation
                if model.messages.count <= 2 {
                    suggestionRow
                }
                inputBar
            }
            .background(WhaleTheme.background)
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AgentOrbView(state: activityState, size: 24)
                        Text("对话")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            model.newConversation()
                        } label: {
                            Label("开启新会话", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { inputFocused = false }
                }
            }
        }
    }

    private var activityState: AgentActivityState {
        if voice.isRecording { return .listening }
        if model.isExecutingTool { return .executing }
        if model.isBusy { return .thinking }
        if model.presentedConfirmation != nil { return .waiting }
        return .idle
    }

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text(model.errorText ?? "服务连接中断，请检查网络后重试。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("重试") {
                Task {
                    await model.health()
                    model.refreshPermissions()
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    ForEach(model.pending) { item in
                        PendingActionCard(item: item, isBusy: model.isBusy) {
                            model.presentedConfirmation = item
                        }
                        .id(item.id)
                    }

                    if model.isBusy {
                        HStack(spacing: 9) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("鲸鱼正在处理…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 44)
                        .id("busy")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture { inputFocused = false }
            .onChange(of: model.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.pending.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.isBusy) {
                if model.isBusy {
                    withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
                }
            }
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                suggestion("明天下午三点提醒我取快递")
                suggestion("帮我看看明天下午的安排")
                suggestion("附近有哪家咖啡店？")
                suggestion("我想听歌")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(WhaleTheme.background)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            model.input = text
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhaleTheme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if voice.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(voice.transcript.isEmpty ? "正在听你说…" : voice.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("停止") { voice.stop() }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.07))
            }

            HStack(alignment: .bottom, spacing: 9) {
                Button {
                    inputFocused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 31, weight: .regular))
                        .foregroundStyle(voice.isRecording ? Color.red : WhaleTheme.accent)
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.45 : 1)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音输入")

                TextField("告诉鲸鱼你想做什么", text: $model.input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    }
                    .disabled(model.isBusy)
                    .submitLabel(.send)
                    .onSubmit { submitFromKeyboard() }

                if inputFocused {
                    Button {
                        inputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起键盘")
                }

                Button {
                    submitFromKeyboard()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(WhaleTheme.accent, in: Circle())
                }
                .disabled(model.isBusy || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(model.isBusy || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 10)

            if let voiceError = voice.errorText {
                Text(voiceError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(.bar)
        .onChange(of: voice.transcript) { _, text in
            guard !text.isEmpty else { return }
            model.input = text
        }
    }

    private func submitFromKeyboard() {
        if voice.isRecording { voice.stop() }
        inputFocused = false
        Task { await model.send() }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = model.pending.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else if let last = model.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.role == .assistant {
                assistantAvatar
            }

            VStack(alignment: .leading, spacing: 5) {
                if message.role == .tool {
                    Label(message.text, systemImage: "iphone.gen3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhaleTheme.accent)
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                }

                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(message.role == .user ? Color.white.opacity(0.72) : Color.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "waveform")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(WhaleTheme.accent, in: Circle())
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return WhaleTheme.accent
        case .assistant: return WhaleTheme.card
        case .tool: return WhaleTheme.accent.opacity(0.08)
        }
    }
}

private struct PendingActionCard: View {
    let item: PendingTool
    let isBusy: Bool
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: ToolPresentation.icon(item.tool))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(WhaleTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ToolPresentation.title(item.tool))
                        .font(.subheadline.weight(.semibold))
                    Text("执行前需要你的确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("待确认")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            Text(ToolPresentation.detail(for: item))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onReview) {
                Text("查看并确认")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(WhaleTheme.accent)
            .disabled(isBusy)
        }
        .whaleCard()
    }
}

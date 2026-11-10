import SwiftUI

struct ConversationTabView: View {
    @ObservedObject var model: AppModel
    @Binding var isDetailOpen: Bool
    let onOpenRecords: () -> Void
    let onOpenSettings: () -> Void

    @State private var showChat = false
    @State private var showVoice = false
    @State private var voiceDraft: String?
    @State private var voiceShouldSend = false
    @State private var autoFocus = false
    @State private var autoVoice = false
    @StateObject private var voice = VoiceInputController()

    var body: some View {
        NavigationStack {
            ChatHomeView(
                model: model,
                onSend: { text in
                    model.input = text
                    autoFocus = false
                    autoVoice = false
                    showChat = true
                    Task { await model.send() }
                },
                onTalk: {
                    model.speech.stop()
                    voice.reset()
                    voiceDraft = nil
                    voiceShouldSend = false
                    showVoice = true
                },
                onType: {
                    model.speech.stop()
                    autoVoice = false
                    autoFocus = true
                    showChat = true
                },
                onOpenRecords: onOpenRecords,
                onOpenSettings: onOpenSettings
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showChat) {
                ChatView(
                    model: model,
                    startVoiceOnAppear: $autoVoice,
                    focusOnAppear: $autoFocus
                )
            }
            .onChange(of: showChat) { _, open in
                isDetailOpen = open
            }
            .sheet(isPresented: $showVoice, onDismiss: handleVoiceDismiss) {
                VoiceView(
                    voice: voice,
                    onSend: { text in
                        voiceDraft = text
                        voiceShouldSend = true
                        showVoice = false
                    },
                    onClose: { text in
                        voiceDraft = text
                        voiceShouldSend = false
                        showVoice = false
                    },
                    onCancel: {
                        voiceDraft = nil
                        voiceShouldSend = false
                        showVoice = false
                    }
                )
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(WhaleTheme.pageGradient)
                .interactiveDismissDisabled(voice.isRecording)
            }
        }
    }

    private func handleVoiceDismiss() {
        defer {
            voiceDraft = nil
            voiceShouldSend = false
        }
        guard let draft = voiceDraft else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.input = text
        autoVoice = false
        if voiceShouldSend {
            guard !text.isEmpty else { return }
            autoFocus = false
            showChat = true
            Task { await model.send(text: text, speakReply: true) }
        } else {
            autoFocus = true
            showChat = true
        }
    }
}

struct ChatHomeView: View {
    @ObservedObject var model: AppModel
    let onSend: (String) -> Void
    let onTalk: () -> Void
    let onType: () -> Void
    let onOpenRecords: () -> Void
    let onOpenSettings: () -> Void

    private let suggestions: [(title: String, prompt: String)] = [
        ("附近吃点什么", "找我附近两公里内的餐厅，帮我看看价格。"),
        ("看看今天安排", "帮我看看今天和最近的日程安排。"),
        ("定个提醒", "帮我定一个提醒。")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("今天想做点什么？")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                        .padding(.top, 30)

                    Text("说一句，我来办。写入系统前会先请你确认。")
                        .font(.system(size: 14))
                        .foregroundStyle(WhaleTheme.muted)
                        .padding(.top, 8)

                    WhaleFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(suggestions.indices, id: \.self) { index in
                            suggestionChip(suggestions[index].title) {
                                onSend(suggestions[index].prompt)
                            }
                        }
                    }
                    .padding(.top, 22)

                    if let recent = model.recentActions.first {
                        recentCard(recent)
                    }

                    if model.isBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.statusLine)
                                .font(.system(size: 13))
                                .foregroundStyle(WhaleTheme.muted)
                                .lineLimit(2)
                        }
                        .padding(.top, 22)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            composer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("鲸鱼")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("随时和我说")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
            Button(action: onOpenRecords) {
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("任务与记录")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func suggestionChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WhaleTheme.ink)
                .whaleChip()
        }
        .buttonStyle(.plain)
    }

    private func recentCard(_ action: NativeActionRecord) -> some View {
        Button(action: onOpenRecords) {
            HStack(spacing: 12) {
                WhaleIconTile(systemName: action.icon, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近一次")
                        .font(.system(size: 12))
                        .foregroundStyle(WhaleTheme.muted)
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Text(action.isSuccess ? "已完成" : "待核对")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(action.isSuccess ? WhaleTheme.success : WhaleTheme.warm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
            }
            .whaleCard(padding: 14)
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
        .accessibilityHint("打开任务与记录")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button(action: onType) {
                HStack(spacing: 10) {
                    Text("有什么想说的…")
                        .font(.system(size: 16))
                        .foregroundStyle(WhaleTheme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("输入消息")

            Button(action: onTalk) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(WhaleTheme.heroGradient, in: Circle())
                    .shadow(color: WhaleTheme.accent.opacity(0.32), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("语音输入")
            .accessibilityHint("打开语音对话")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

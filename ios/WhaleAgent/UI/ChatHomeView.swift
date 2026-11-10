import SwiftUI

struct ConversationTabView: View {
    @ObservedObject var model: AppModel
    let onOpenMusic: () -> Void

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
                    voice.reset()
                    voiceDraft = nil
                    voiceShouldSend = false
                    showVoice = true
                },
                onType: {
                    autoVoice = false
                    autoFocus = true
                    showChat = true
                },
                onOpenMusic: onOpenMusic
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showChat) {
                ChatView(
                    model: model,
                    startVoiceOnAppear: $autoVoice,
                    focusOnAppear: $autoFocus
                )
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
                .presentationBackground(WhaleTheme.background)
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
            Task { await model.send() }
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
    let onOpenMusic: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 11),
        GridItem(.flexible(), spacing: 11)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    Image("WhaleMascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 188, height: 141)
                        .padding(.top, 14)
                        .accessibilityHidden(true)

                    Text("今天有什么想法？")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                        .padding(.top, 4)

                    Text("聊一聊，或把一件事交给我。")
                        .font(.system(size: 14))
                        .foregroundStyle(WhaleTheme.muted)
                        .padding(.top, 7)

                    Button(action: onTalk) {
                        Label("和鲸鱼说话", systemImage: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 232, height: 52)
                            .background(WhaleTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: WhaleTheme.accent.opacity(0.22), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .accessibilityHint("开始语音对话")

                    LazyVGrid(columns: columns, spacing: 11) {
                        suggestion(
                            icon: "mappin.and.ellipse",
                            title: "附近吃点什么",
                            subtitle: "找店，再看看价格"
                        ) {
                            onSend("找我附近两公里内的餐厅，帮我看看价格。")
                        }
                        suggestion(
                            icon: "music.note",
                            title: "听点音乐",
                            subtitle: "从自己的曲库开始"
                        ) {
                            onOpenMusic()
                        }
                    }
                    .padding(.top, 27)

                    Button {
                        onSend("帮我看看这段通知里有什么需要安排的。")
                    } label: {
                        Label("也可以发来一篇通知，接着安排。", systemImage: "doc.text")
                            .font(.system(size: 13))
                            .foregroundStyle(WhaleTheme.muted)
                            .frame(minHeight: 44)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            composer
        }
        .background(WhaleTheme.background)
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
            Button {
                model.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("开启新会话")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func suggestion(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(WhaleTheme.accent)
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
            .padding(16)
            .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(WhaleTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        Button(action: onType) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(WhaleTheme.muted)
                Text("有什么想说的…")
                    .font(.system(size: 16))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(WhaleTheme.card, in: Capsule())
            .overlay {
                Capsule().strokeBorder(WhaleTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel("输入消息")
    }
}

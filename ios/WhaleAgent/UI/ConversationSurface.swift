import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The single conversation surface. Sending, voice and results all stay on the
/// home page; nothing is pushed and no voice sheet is presented.
struct ConversationSurface: View {
    @ObservedObject var model: AppModel
    let keyboardTop: CGFloat?
    let onOpenRecords: () -> Void

    @StateObject private var voice = VoiceInputController()
    @FocusState private var inputFocused: Bool
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var pageBottom: CGFloat = 0

    private let suggestions: [(title: String, prompt: String)] = [
        ("附近吃点什么", "找我附近两公里内的餐厅，帮我看看价格。"),
        ("看看今天安排", "帮我看看今天和最近的日程安排。"),
        ("定个提醒", "帮我定一个提醒。")
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !model.backendOnline || model.errorText != nil {
                connectionBanner
            }

            if model.messages.isEmpty {
                homeCanvas
            } else {
                conversation
            }

            composer
                .padding(.bottom, keyboardInset)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PageBottomKey.self, value: geo.frame(in: .global).maxY)
            }
        }
        .onPreferenceChange(PageBottomKey.self) { pageBottom = $0 }
        .onChange(of: voice.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard voice.errorText == nil else { return }
            if !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputFocused = true
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images, photoLibrary: .shared())
        .onChange(of: photoItem) { _, _ in
            Task { await ingestPhoto() }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
    }

    // MARK: - Empty home

    private var homeCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("今天想做点什么？")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                    .padding(.top, 28)

                Text("说一句，我来办。写入系统前会先请你确认。")
                    .font(.system(size: 14))
                    .foregroundStyle(WhaleTheme.muted)
                    .padding(.top, 8)

                WhaleFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(suggestions.indices, id: \.self) { index in
                        Button {
                            send(suggestions[index].prompt)
                        } label: {
                            Text(suggestions[index].title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WhaleTheme.ink)
                                .whaleChip()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                if let recent = model.recentActions.first {
                    recentCard(recent)
                }

                if model.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.statusLine)
                            .font(.system(size: 13))
                            .foregroundStyle(WhaleTheme.muted)
                            .lineLimit(2)
                    }
                    .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WhaleTheme.pagePadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func recentCard(_ action: OperationRecord) -> some View {
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

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        MessageRow(
                            message: message,
                            isSpeaking: model.isSpeakingReply && model.speakingMessageId == message.id.uuidString,
                            onToggleSpeech: { model.toggleSpeech(for: message) }
                        )
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
                            ProgressView().scaleEffect(0.75)
                            Text("鲸鱼正在处理…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 44)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .onTapGesture { inputFocused = false }
            .onChange(of: model.messages.count) { _, _ in
                pinToBottom(proxy)
            }
            .onChange(of: model.pending.count) { _, _ in
                pinToBottom(proxy)
            }
            .onChange(of: model.isBusy) { _, busy in
                if busy { pinToBottom(proxy) }
            }
            .onChange(of: keyboardInset) { _, _ in
                DispatchQueue.main.async { pinToBottom(proxy, animated: false) }
            }
            .onAppear {
                DispatchQueue.main.async { pinToBottom(proxy, animated: false) }
            }
        }
    }

    private static let bottomAnchor = "conversationBottom"

    private var keyboardInset: CGFloat {
        guard let keyboardTop, pageBottom > 0 else { return 0 }
        return max(0, pageBottom - keyboardTop)
    }

    /// Keeps the newest message pinned. Only content changes move the list;
    /// typing never does, so the scroll position stays put while composing.
    private func pinToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.22), scroll)
        } else {
            scroll()
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(WhaleTheme.warm)
            Text(model.errorText ?? "服务连接中断，请检查网络后重试。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .lineLimit(2)
            Spacer()
            Button("重试") {
                Task {
                    await model.health()
                    model.refreshPermissions()
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .tint(WhaleTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(WhaleTheme.warm.opacity(0.10))
    }

    // MARK: - Composer

    private var composer: some View {
        ConversationComposer(
            model: model,
            voice: voice,
            focused: $inputFocused,
            importError: importError,
            onPickPhoto: { showPhotoPicker = true },
            onPickFile: { showFileImporter = true }
        )
    }

    private func send(_ text: String) {
        inputFocused = false
        Task { await model.send(text: text) }
    }

    private func ingestPhoto() async {
        guard let item = photoItem else { return }
        photoItem = nil
        importError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "没有读到照片数据，请换一张图片。"
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("whale-ocr-\(UUID().uuidString).jpg")
            try data.write(to: url, options: .atomic)
            await model.ingestDocument(url: url, label: "照片")
            try? FileManager.default.removeItem(at: url)
        } catch {
            importError = photoImportMessage(error)
        }
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if access { url.stopAccessingSecurityScopedResource() }
                }
                let label = url.pathExtension.lowercased() == "pdf" ? "PDF" : "图片"
                await model.ingestDocument(url: url, label: label)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func photoImportMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "照片读取失败：当前网络不可用。若这张照片只存在 iCloud，请先联网下载原图，或改用“从文件识别”选择本机图片。"
        }
        if ns.domain.contains("Photo") || ns.domain.contains("Cloud") {
            return "照片读取失败：\(error.localizedDescription)。请在相册中先下载到本机后重试。"
        }
        return "照片读取失败：\(error.localizedDescription)"
    }
}

/// Composer lives in its own view so typing only invalidates this subtree.
/// The message list above never re-renders while the user is composing.
private struct ConversationComposer: View {
    @ObservedObject var model: AppModel
    @ObservedObject var voice: VoiceInputController
    @FocusState.Binding var focused: Bool
    let importError: String?
    let onPickPhoto: () -> Void
    let onPickFile: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if voice.isRecording {
                voiceStrip
            }

            HStack(alignment: .bottom, spacing: 9) {
                Menu {
                    Button(action: onPickPhoto) {
                        Label("从照片识别", systemImage: "photo")
                    }
                    Button(action: onPickFile) {
                        Label("从文件识别 PDF/图片", systemImage: "doc")
                    }
                } label: {
                    Group {
                        if model.isExtractingDocument {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(WhaleTheme.ink)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || model.isExtractingDocument)
                .opacity(model.isBusy || model.isExtractingDocument ? 0.45 : 1)
                .accessibilityLabel("导入照片或文件识别文字")

                Button {
                    focused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(voice.isRecording ? WhaleTheme.danger : WhaleTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.45 : 1)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音输入")

                TextField("告诉鲸鱼你想做什么", text: $draft)
                    .lineLimit(1)
                    .frame(height: 22)
                    .focused($focused)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                    }
                    .disabled(model.isBusy)
                    .submitLabel(.send)
                    .onSubmit { submit() }

                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(focused)
                .accessibilityHidden(!focused)
                .accessibilityLabel("收起键盘")

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(WhaleTheme.accent, in: Circle())
                }
                .disabled(model.isBusy || isDraftEmpty)
                .opacity(model.isBusy || isDraftEmpty ? 0.45 : 1)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 10)

            if let voiceError = voice.errorText {
                Text(voiceError)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.warm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if let importError {
                Text(importError)
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.warm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhaleTheme.glassStroke)
                .frame(height: 0.5)
        }
        .onChange(of: voice.transcript) { _, text in
            guard !text.isEmpty else { return }
            draft = text
        }
        .onChange(of: model.messages.isEmpty) { _, empty in
            if empty { draft = "" }
        }
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var voiceStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(WhaleTheme.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(voice.transcript.isEmpty ? "正在听你说…" : voice.transcript)
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.muted)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("停止") { voice.stop() }
                .font(.system(size: 13, weight: .semibold))
                .tint(WhaleTheme.danger)
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleTheme.danger.opacity(0.07))
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if voice.isRecording {
            voice.stop()
        }
        focused = false
        draft = ""
        Task { await model.send(text: text) }
    }
}

private struct PageBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

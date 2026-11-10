import SwiftUI
import UIKit

/// The single conversation surface. Sending, voice and results all stay on the
/// home page; nothing is pushed and no voice sheet is presented.
///
/// The composer is intentionally excluded from this view: it lives at the root
/// above the horizontal pager, so focusing the text field cannot make the pager
/// scroll or resize the message list.
struct ConversationSurface: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void

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
            .padding(.bottom, 24 + bottomInset)
        }
        .scrollIndicators(.hidden)
        .onTapGesture { dismissKeyboard() }
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
                .padding(.bottom, 20 + bottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .onTapGesture { dismissKeyboard() }
            .onChange(of: model.messages.count) { _, _ in
                pinToBottom(proxy)
            }
            .onChange(of: model.pending.count) { _, _ in
                pinToBottom(proxy)
            }
            .onChange(of: model.isBusy) { _, busy in
                if busy { pinToBottom(proxy) }
            }
            .onChange(of: bottomInset) { oldInset, newInset in
                guard newInset > oldInset else { return }
                DispatchQueue.main.async { pinToBottom(proxy, animated: false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    pinToBottom(proxy, animated: false)
                }
            }
            .onAppear {
                DispatchQueue.main.async { pinToBottom(proxy, animated: false) }
            }
        }
    }

    private static let bottomAnchor = "conversationBottom"

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

    private func send(_ text: String) {
        dismissKeyboard()
        Task { await model.send(text: text) }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
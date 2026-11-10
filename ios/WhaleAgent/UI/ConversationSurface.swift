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
        WhaleHomeCanvas(
            model: model,
            bottomInset: bottomInset,
            onOpenRecords: onOpenRecords
        )
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
                        .frame(height: 20 + bottomInset)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
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

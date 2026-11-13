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
    @State private var followState = ConversationFollowState()
    @State private var userScrolling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !model.backendOnline || model.errorText != nil {
                connectionBanner
            }
            conversation
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if model.messages.isEmpty && model.pending.isEmpty && !model.isBusy { emptyConversation }
                        ForEach(model.messages) { message in
                            MessageRow(message: message,
                                isSpeaking: model.isSpeakingReply && model.speakingMessageId == message.id.uuidString,
                                onToggleSpeech: { model.toggleSpeech(for: message) }).id(message.id)
                        }
                        ForEach(model.pending) { item in
                            PendingActionCard(item: item, isBusy: model.isBusy) {
                                if item.tool == "create_reminder" { Task { await model.confirm(item) } }
                                else { model.presentedConfirmation = item }
                            }.id(item.id)
                        }
                        AssistantActivityView(model: model)
                        Color.clear.frame(height: 20 + bottomInset).id(Self.bottomAnchor)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: ConversationBottomKey.self, value: geometry.frame(in: .named("conversation-viewport")).maxY)
                            })
                    }.padding(.horizontal, 16).padding(.top, 16)
                }
                .coordinateSpace(name: "conversation-viewport")
                .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.bottom)
                .background(ScrollOffsetMemory(key: "chat-" + model.composerContextID, onRestored: { near in followState.updatePosition(nearBottom: near) }, startAtBottom: true))
                .simultaneousGesture(DragGesture(minimumDistance: 2)
                    .onChanged { _ in userScrolling = true }
                    .onEnded { _ in Task { try? await Task.sleep(nanoseconds: 700_000_000); userScrolling = false } })
                .onPreferenceChange(ConversationBottomKey.self) { bottom in
                    let near = bottom <= viewport.size.height + 70
                    if near || userScrolling { followState.updatePosition(nearBottom: near) }
                }
                .onChange(of: model.messages.count) { old, new in
                    guard new > old else { return }
                    if followState.receive(new - old) { pinToBottom(proxy) }
                }
                .onChange(of: model.pending.count) { _, _ in
                    if followState.receive() { pinToBottom(proxy) }
                }
                .onChange(of: viewport.size.height) { _, _ in
                    if followState.nearBottom { pinToBottom(proxy, animated: false) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if followState.unread > 0 {
                        Button {
                            followState.follow(); pinToBottom(proxy)
                        } label: {
                            Label("\(followState.unread) 条新内容", systemImage: "arrow.down")
                                .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                .background(WhaleTheme.card, in: Capsule()).overlay(Capsule().stroke(WhaleTheme.line))
                        }.foregroundStyle(WhaleTheme.accent).padding(16)
                    }
                }
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 12) {
            WhaleMarkView(size: 62)
            Text("开始和鲸鱼说话")
                .whaleFont(size: 19, weight: .bold, design: .rounded)
                .foregroundStyle(WhaleTheme.ink)
            Text("直接输入，或点下方麦克风说一句。\n消息、执行结果和待确认操作都会留在这个页面。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.bottom, 24)
    }

    private static let bottomAnchor = "conversationBottom"

    /// Keeps the newest message pinned. Only content changes move the list;
    /// typing never does, so the scroll position stays put while composing.
    private func pinToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        if animated && !reduceMotion {
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
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .lineLimit(2)
            Spacer()
            Button("重试") {
                Task {
                    await model.retryCurrentRequest()
                    model.refreshPermissions()
                }
            }
            .whaleFont(size: 13, weight: .semibold)
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

private struct ConversationBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

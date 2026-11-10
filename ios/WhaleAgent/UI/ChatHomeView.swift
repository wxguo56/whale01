import SwiftUI

/// Root conversation page. The new-conversation screen and the running
/// conversation are two states of the same tab; a left-edge swipe (or the
/// header chevron) goes back to the starter without deleting the messages.
struct ConversationTabView: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void
    let onOpenSettings: () -> Void

    @State private var browsingStarter = false

    private var showingStarter: Bool {
        model.messages.isEmpty || browsingStarter
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if showingStarter {
                    WhaleHomeCanvas(
                        model: model,
                        bottomInset: bottomInset,
                        onOpenRecords: onOpenRecords,
                        onResumeConversation: model.messages.isEmpty ? nil : { goToConversation() }
                    )
                    .transition(.opacity)
                } else {
                    ConversationSurface(
                        model: model,
                        bottomInset: bottomInset,
                        onOpenRecords: onOpenRecords
                    )
                    .transition(.opacity)
                    .overlay(alignment: .leading) {
                        ConversationBackSwipe(isEnabled: true, onBack: goToStarter)
                            .frame(width: 22)
                            .frame(maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingStarter)
        }
        .onChange(of: model.messages.count) { oldCount, newCount in
            if newCount > oldCount || newCount == 0 {
                browsingStarter = false
            }
        }
    }

    private func goToStarter() {
        guard !model.messages.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            browsingStarter = true
        }
    }

    private func goToConversation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            browsingStarter = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !showingStarter && !model.messages.isEmpty {
                Button(action: goToStarter) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle(size: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回新对话")
                .transition(.opacity)
            }

            WhaleMarkView(size: showingStarter ? 40 : 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("鲸鱼")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                    Text("BETA")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(WhaleTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(WhaleTheme.accent.opacity(0.11), in: Capsule())
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    browsingStarter = false
                    model.newConversation()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                    Text("新对话")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(WhaleTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开启新会话")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background {
            WhaleChromeBackground()
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WhaleTheme.glassStroke)
                .frame(height: 0.5)
        }
        .animation(.easeInOut(duration: 0.2), value: showingStarter)
    }

    private var statusText: String {
        if model.isExecutingTool { return "正在执行设备操作…" }
        if model.isBusy { return "正在处理…" }
        if !model.backendOnline { return "当前离线" }
        if let track = model.playback.track {
            return track.isLocal ? "正在连接你的本机音乐" : "随时和我说"
        }
        return "说一句，鲸鱼来办"
    }

    private var statusColor: Color {
        if model.isBusy || model.isExecutingTool { return WhaleTheme.coral }
        if !model.backendOnline { return WhaleTheme.warm }
        return WhaleTheme.success
    }
}
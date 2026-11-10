import SwiftUI

/// Root conversation page. The new-conversation screen and the running
/// conversation are two states of the same tab; a left-edge swipe (or the
/// header chevron) goes back to the starter without deleting the messages.
struct ConversationTabView: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    let onOpenRecords: () -> Void
    let onOpenSettings: () -> Void
    let onOpenMusic: () -> Void

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
                        onOpenMusic: onOpenMusic,
                        onResumeConversation: model.messages.isEmpty ? nil : { goToConversation() }
                    )
                    .transition(.opacity)
                } else {
                    ConversationSurface(
                        model: model,
                        bottomInset: bottomInset,
                        onOpenRecords: onOpenRecords,
                        onOpenMusic: onOpenMusic
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

            if let track = model.playback.track {
                Spacer(minLength: 3)
                Button(action: onOpenMusic) {
                    MiniVinylView(track: track, isPlaying: model.playback.isPlaying)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("正在播放 \(track.title)，打开音乐")
                Spacer(minLength: 2)
            } else {
                Spacer(minLength: 6)
                Button(action: onOpenMusic) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle(size: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开音乐")
            }

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
            let prefix = model.playback.isPlaying ? "正在播放" : "已暂停"
            return "\(prefix) · \(track.title)"
        }
        return "说一句，鲸鱼来办"
    }

    private var statusColor: Color {
        if model.isBusy || model.isExecutingTool { return WhaleTheme.coral }
        if !model.backendOnline { return WhaleTheme.warm }
        return WhaleTheme.success
    }
}

/// Small spinning vinyl record shown in the header while music is active.
/// It keeps playback controls out of the bottom safe area.
private struct MiniVinylView: View {
    let track: MusicTrackItem
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = Date()
    @State private var baseAngle: Double = 0

    private let diameter: CGFloat = 38
    private let degreesPerSecond: Double = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { context in
            vinyl(angle: currentAngle(at: context.date))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onChange(of: isPlaying) { _, playing in
            if playing {
                anchor = Date()
            } else {
                baseAngle = liveAngle(at: Date()).truncatingRemainder(dividingBy: 360)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private func currentAngle(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return baseAngle }
        return liveAngle(at: date).truncatingRemainder(dividingBy: 360)
    }

    private func liveAngle(at date: Date) -> Double {
        baseAngle + max(0, date.timeIntervalSince(anchor)) * degreesPerSecond
    }

    private func vinyl(angle: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.19), Color(white: 0.04)],
                        center: .center,
                        startRadius: 1,
                        endRadius: diameter / 2
                    )
                )

            ForEach([0.88, 0.76, 0.64, 0.52], id: \.self) { scale in
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.55)
                    .frame(width: diameter * scale, height: diameter * scale)
            }

            Circle()
                .trim(from: 0.02, to: 0.11)
                .stroke(Color.white.opacity(0.22), lineWidth: 1.1)
                .padding(2.4)
                .rotationEffect(.degrees(-52))

            label
                .frame(width: diameter * 0.44, height: diameter * 0.44)
                .clipShape(Circle())

            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: 2.6, height: 2.6)
        }
        .rotationEffect(.degrees(angle))
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 5, y: 2)
    }

    @ViewBuilder
    private var label: some View {
        if let image = track.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [WhaleTheme.accent, WhaleTheme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }
}

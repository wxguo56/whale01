import SwiftUI

struct VoiceView: View {
    @ObservedObject var voice: VoiceInputController
    let onSend: (String) -> Void
    let onClose: (String) -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                mascot
                Text(stateTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                    .padding(.top, 24)
                Text(stateCaption)
                    .font(.system(size: 16))
                    .foregroundStyle(WhaleTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
                    .padding(.top, 10)
                    .frame(minHeight: 52, alignment: .top)
                waveBars
                    .padding(.top, 26)
                if let error = voice.errorText {
                    errorCard(error)
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                }
                if canSend {
                    Button {
                        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        voice.reset()
                        onSend(text)
                    } label: {
                        Label("发给鲸鱼", systemImage: "arrow.up")
                            .whalePrimaryButton()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 34)
                    .padding(.top, 22)
                }
                Spacer(minLength: 12)
                footer
            }
        }
        .task {
            startPulse()
            await voice.start()
        }
        .onDisappear {
            voice.stop()
        }
    }

    private var background: some View {
        ZStack {
            WhaleTheme.background
            RadialGradient(
                colors: [WhaleTheme.accentSoft.opacity(0.9), WhaleTheme.background.opacity(0)],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                voice.stop()
                onClose(voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("转文字")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WhaleTheme.accent)
                    .frame(minWidth: 64, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var mascot: some View {
        ZStack {
            Circle()
                .stroke(WhaleTheme.accent.opacity(0.16), lineWidth: 1)
                .frame(width: 246, height: 246)
                .scaleEffect(pulse ? 1.04 : 0.94)
                .opacity(pulse ? 0.5 : 1)
            Circle()
                .fill(WhaleTheme.accent.opacity(0.06))
                .frame(width: 206, height: 206)
                .scaleEffect(pulse ? 0.96 : 1.04)
            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 214, height: 160)
                .offset(y: -4)
        }
        .frame(height: 250)
        .accessibilityHidden(true)
    }

    private var waveBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !voice.isRecording)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<17, id: \.self) { index in
                    let swing = voice.isRecording
                        ? 0.4 + 0.6 * abs(sin(time * 3.1 + Double(index) * 0.52))
                        : 0.35
                    Capsule()
                        .fill(voice.isRecording ? WhaleTheme.accent : WhaleTheme.muted.opacity(0.35))
                        .frame(width: 4, height: barHeight(index) * CGFloat(swing))
                }
            }
            .frame(height: 46)
        }
        .opacity(voice.isRecording ? 1 : 0.55)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 56) {
                Button {
                    voice.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 52, height: 52)
                        .background(WhaleTheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(WhaleTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新开始")

                Button {
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 78, height: 78)
                        .background(voice.isRecording ? WhaleTheme.accent : WhaleTheme.accentDeep, in: Circle())
                        .shadow(color: WhaleTheme.accent.opacity(0.28), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voice.isRecording ? "停止倾听" : "开始说话")

                Button {
                    voice.stop()
                    onClose(voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .frame(width: 52, height: 52)
                        .background(WhaleTheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(WhaleTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束语音")
            }

            Text("随时停止，或回到文字继续。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
        }
        .padding(.bottom, 22)
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "mic.slash")
                .foregroundStyle(WhaleTheme.warm)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhaleTheme.line, lineWidth: 1)
        }
    }

    private var stateTitle: String {
        if voice.errorText != nil { return "还没听到" }
        if voice.isRecording { return "我在听" }
        if !voice.transcript.isEmpty { return "听清了" }
        return "准备好了"
    }

    private var stateCaption: String {
        if voice.isRecording {
            return voice.transcript.isEmpty ? "说说你想做什么。" : voice.transcript
        }
        if !voice.transcript.isEmpty {
            return voice.transcript
        }
        return "点一下下方按钮，开始说话。"
    }

    private var canSend: Bool {
        !voice.isRecording && !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [12, 20, 30, 38, 28, 18, 26, 36, 42, 32, 22, 30, 40, 30, 22, 16, 12]
        return pattern[index % pattern.count]
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

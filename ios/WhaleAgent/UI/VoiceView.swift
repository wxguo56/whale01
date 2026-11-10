import SwiftUI

struct VoiceView: View {
    @ObservedObject var voice: VoiceInputController
    let onSend: (String) -> Void
    let onClose: (String) -> Void
    let onCancel: () -> Void

    @State private var pulse = false
    @State private var localHint: String?
    @State private var isFinishing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 4)
            mascot

            Text(stateTitle)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)
                .padding(.top, 2)

            Text(stateCaption)
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(2)
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .frame(minHeight: 42, alignment: .top)

            waveBars
                .padding(.top, 6)

            if let error = visibleError {
                errorCard(error)
                    .padding(.horizontal, 26)
                    .padding(.top, 6)
            }

            Spacer(minLength: 6)
            controls
            Text("停止后自动发送，或转成文字继续编辑。")
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .padding(.top, 10)
        }
        .padding(.bottom, 12)
        .task {
            startPulse()
        }
        .onDisappear {
            voice.stop()
        }
        .onChange(of: voice.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, !isFinishing, voice.errorText == nil else { return }
            let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            isFinishing = true
            onSend(text)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("语音对话")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(voice.isRecording ? "正在听你说话" : "轻点麦克风开始")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Spacer()

            Button {
                finishToText()
            } label: {
                Text("转文字")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WhaleTheme.accent)
                    .frame(minWidth: 54, minHeight: 40)
            }
            .buttonStyle(.plain)

            Button {
                cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(WhaleTheme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消语音输入")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var mascot: some View {
        ZStack {
            Circle()
                .stroke(WhaleTheme.accent.opacity(0.14), lineWidth: 1)
                .frame(width: 150, height: 150)
                .scaleEffect(pulse ? 1.04 : 0.95)
                .opacity(pulse ? 0.55 : 1)
            Circle()
                .fill(WhaleTheme.accent.opacity(0.07))
                .frame(width: 124, height: 124)
                .scaleEffect(pulse ? 0.97 : 1.03)
            Image("WhaleMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 138, height: 104)
        }
        .frame(height: 142)
        .accessibilityHidden(true)
    }

    private var waveBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !voice.isRecording)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<15, id: \.self) { index in
                    let swing = voice.isRecording
                        ? 0.4 + 0.6 * abs(sin(time * 3.1 + Double(index) * 0.55))
                        : 0.32
                    Capsule()
                        .fill(WhaleTheme.accent.opacity(voice.isRecording ? 0.9 : 0.35))
                        .frame(width: 3, height: barHeight(index) * CGFloat(swing))
                }
            }
            .frame(height: 30)
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 38) {
            Button {
                restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 46, height: 46)
                    .background(WhaleTheme.card, in: Circle())
                    .overlay(Circle().strokeBorder(WhaleTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新开始")

            Button {
                primaryAction()
            } label: {
                Image(systemName: primaryIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(voice.isRecording ? WhaleTheme.accent : WhaleTheme.accentDeep, in: Circle())
                    .shadow(color: WhaleTheme.accent.opacity(0.25), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryLabel)

            Button {
                finishToText()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 46, height: 46)
                    .background(WhaleTheme.card, in: Circle())
                    .overlay(Circle().strokeBorder(WhaleTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("转成文字")
        }
    }

    private var visibleError: String? {
        localHint ?? voice.errorText
    }

    private var stateTitle: String {
        if localHint != nil { return "还没听清" }
        if voice.errorText != nil { return "需要用文字" }
        if voice.isRecording { return "我在听" }
        if !voice.transcript.isEmpty { return "听清了" }
        return "准备好了"
    }

    private var stateCaption: String {
        if let localHint { return localHint }
        if let error = voice.errorText { return error }
        if voice.isRecording {
            return voice.transcript.isEmpty ? "说说你想做什么。" : voice.transcript
        }
        if !voice.transcript.isEmpty { return voice.transcript }
        return "点一下麦克风开始说话。"
    }

    private var primaryIcon: String {
        if voice.isRecording { return "stop.fill" }
        if canSend { return "arrow.up" }
        return "mic.fill"
    }

    private var primaryLabel: String {
        if voice.isRecording { return "停止并发送" }
        if canSend { return "发送语音内容" }
        return "开始说话"
    }

    private var canSend: Bool {
        !voice.isRecording && !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func primaryAction() {
        if voice.isRecording || canSend {
            finishAndSend()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        localHint = nil
        isFinishing = false
        Task { await voice.start() }
    }

    private func restart() {
        localHint = nil
        isFinishing = false
        voice.reset()
        Task { await voice.start() }
    }

    private func finishAndSend() {
        guard !isFinishing else { return }
        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            voice.stop()
            localHint = "还没听到内容，请再说一次。"
            return
        }
        isFinishing = true
        voice.stop()
        onSend(text)
    }

    private func finishToText() {
        guard !isFinishing else { return }
        isFinishing = true
        voice.stop()
        onClose(voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func cancel() {
        guard !isFinishing else { return }
        isFinishing = true
        voice.stop()
        onCancel()
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.warm)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WhaleTheme.line, lineWidth: 1)
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [10, 17, 25, 31, 23, 15, 22, 29, 34, 26, 18, 24, 32, 24, 17]
        return pattern[index % pattern.count]
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

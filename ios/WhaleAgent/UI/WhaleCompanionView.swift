import SwiftUI
import AVFoundation
import MediaPlayer

/// Uses the selected Aurora full-body pose assets. Pose switching and whole
/// body movement are implemented here; an independently rigged tail/fin layer
/// requires separate art and is deliberately not claimed by this component.
struct WhaleCompanionView: View {
    enum Mood: String, CaseIterable { case neutral, happy, curious, surprised, sad, crying, sleepy, tired, sleeping }
    var listening = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("whale.companion.sound") private var soundEnabled = false
    @State private var mood: Mood = .neutral
    @State private var floating = false
    @State private var jumping = false
    @State private var actionToken = UUID()
    @State private var busy = false
    @State private var returnTask: Task<Void, Never>?

    var body: some View {
        Image("Aurora-\(listening ? "curious" : mood.rawValue)")
            .resizable().scaledToFit()
            .offset(y: reduceMotion ? 0 : (jumping ? -18 : floating ? -3 : 3))
            .rotationEffect(.degrees(reduceMotion || !jumping ? 0 : -5))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { react(.surprised, jump: true) }
            .onTapGesture { react(mood == .sleeping ? .curious : .happy, jump: true) }
            .onLongPressGesture(minimumDuration: 0.55) { react(.happy, jump: false) }
            .contextMenu {
                ForEach(Mood.allCases, id: \.rawValue) { expression in
                    Button(label(expression)) { react(expression, jump: false) }
                }
                Toggle("触摸音效（合成）", isOn: $soundEnabled)
            }
            .task { startIdle() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { startIdle() } else { resetInteraction() }
            }
            .onDisappear { resetInteraction() }
            .accessibilityLabel("鲸鱼伙伴 · \(label(listening ? .curious : mood))")
            .accessibilityHint("轻点会开心跳动；长按可预览表情与开启合成触摸音效。")
            .accessibilityAddTraits(.isButton)
    }

    private func startIdle() {
        guard !reduceMotion, scenePhase == .active else { return }
        withAnimation(.easeInOut(duration: 2.9).repeatForever(autoreverses: true)) { floating = true }
    }
    private func resetInteraction() {
        returnTask?.cancel()
        returnTask = nil
        actionToken = UUID()
        busy = false
        jumping = false
        floating = false
        mood = .neutral
        CompanionAudio.shared.stop()
    }
    private func react(_ expression: Mood, jump: Bool) {
        guard !busy else { return }
        busy = true
        let token = UUID(); actionToken = token
        mood = expression
        if soundEnabled && !listening { CompanionAudio.shared.play() }
        if !reduceMotion { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { jumping = jump } }
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, actionToken == token else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)) { jumping = false }
            try? await Task.sleep(nanoseconds: expression == .crying ? 3_000_000_000 : 1_000_000_000)
            guard !Task.isCancelled, actionToken == token else { return }
            // Sadness/crying only arise from explicit previews, never from an
            // absent user or a tool failure. Companion mood cannot confirm work.
            mood = .neutral
            busy = false
        }
    }
    private func label(_ mood: Mood) -> String {
        switch mood {
        case .neutral: return "平静"
        case .happy: return "开心"
        case .curious: return "认真倾听"
        case .surprised: return "惊喜"
        case .sad: return "沮丧预览"
        case .crying: return "哭泣预览"
        case .sleepy: return "困了"
        case .tired: return "累了"
        case .sleeping: return "呼呼大睡"
        }
    }
}

@MainActor
private final class CompanionAudio {
    static let shared = CompanionAudio()
    private var player: AVAudioPlayer?
    private var lease: UUID?
    private var lastPlayed = Date.distantPast
    private var finishTask: Task<Void, Never>?
    func play() {
        guard AudioSessionCoordinator.shared.owner == nil,
              MPMusicPlayerController.systemMusicPlayer.playbackState != .playing,
              Date().timeIntervalSince(lastPlayed) >= 1.8,
              let url = Bundle.main.url(forResource: "whale-touch", withExtension: "wav") else { return }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            lease = try AudioSessionCoordinator.shared.acquire(.companion) { [weak self] in self?.stop() }
            audio.volume = 0.3
            player = audio
            guard audio.play() else { stop(); return }
            lastPlayed = Date()
            let duration = audio.duration
            finishTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch { stop() }
    }
    func stop() {
        finishTask?.cancel(); finishTask = nil
        player?.stop(); player = nil
        AudioSessionCoordinator.shared.release(lease); lease = nil
    }
}

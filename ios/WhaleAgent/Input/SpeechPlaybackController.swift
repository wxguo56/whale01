import AVFoundation
import Foundation

extension Notification.Name {
    /// Posted the moment any voice recording starts so playback can be cut off.
    static let whaleInterruptSpeech = Notification.Name("whale.speech.interrupt")
}

/// Speaks assistant replies with the system voice.
///
/// The speaker is intentionally interruptible: starting a new recording, sending
/// a new message, or tapping the stop control cancels the current utterance
/// immediately instead of queueing it behind the old one.
@MainActor
final class SpeechPlaybackController: NSObject, ObservableObject {
    static let enabledKey = "whale.voiceReplyEnabled"

    @Published private(set) var isSpeaking = false
    var onStateChange: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var isSessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled {
            stop()
        }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        activateSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05

        isSpeaking = true
        onStateChange?(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if isSpeaking {
            isSpeaking = false
            onStateChange?(false)
        }
        deactivateSession()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isSessionActive = true
        } catch {
            // 播报失败不阻断对话；文字回复仍然可用。
            isSessionActive = false
        }
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SpeechPlaybackController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onStateChange?(false)
            self.deactivateSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onStateChange?(false)
            self.deactivateSession()
        }
    }
}

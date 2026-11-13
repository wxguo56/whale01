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
    private var audioLease: UUID?
    private var currentUtterance: AVSpeechUtterance?

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
        guard activateSession() else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05

        currentUtterance = utterance
        isSpeaking = true
        onStateChange?(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if isSpeaking {
            isSpeaking = false
            onStateChange?(false)
        }
        deactivateSession()
    }

    private func activateSession() -> Bool {
        do {
            audioLease = try AudioSessionCoordinator.shared.acquire(.speech) { [weak self] in self?.stop() }
            return true
        } catch { return false }
    }

    private func deactivateSession() {
        AudioSessionCoordinator.shared.release(audioLease)
        audioLease = nil
    }

}

extension SpeechPlaybackController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
            self.onStateChange?(false)
            self.deactivateSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
            self.onStateChange?(false)
            self.deactivateSession()
        }
    }
}

import AVFoundation
import Foundation

/// One owner at a time. An old recognition/TTS callback can only release its
/// own lease, never deactivate a newer recording or music session.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    enum Owner: Int { case companion = 0, music, speech, recording }
    private(set) var owner: Owner?
    private var lease: UUID?
    private var onLoss: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.interrupt() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.interrupt() }
        })
    }

    func acquire(_ requested: Owner, onLoss: @escaping () -> Void) throws -> UUID {
        if let owner, owner.rawValue > requested.rawValue {
            throw ToolExecutionError(code: "audio_busy", message: "麦克风或语音正在使用音频，请结束后再播放。")
        }
        interrupt(deactivate: false)
        let session = AVAudioSession.sharedInstance()
        switch requested {
        case .recording: try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        case .speech: try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .music: try session.setCategory(.playback, mode: .default)
        case .companion: try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
        let token = UUID()
        lease = token; owner = requested; self.onLoss = onLoss
        return token
    }

    func release(_ token: UUID?) {
        guard let token, lease == token else { return }
        lease = nil; owner = nil; onLoss = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func interrupt(deactivate: Bool = true) {
        let callback = onLoss
        lease = nil; owner = nil; onLoss = nil
        callback?()
        if deactivate { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

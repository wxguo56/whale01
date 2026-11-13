import AVFoundation
import Combine
import Foundation

enum LocalMusicPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var media: URL {
        documents.appendingPathComponent("Music", isDirectory: true)
    }

    static var index: URL {
        documents.appendingPathComponent("music-library.json")
    }
}

struct LocalTrack: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var artist: String
    var fileName: String
    var durationSec: Double
    var addedAt: Date

    var durationText: String {
        guard durationSec > 0 else { return "" }
        let seconds = Int(durationSec.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Plays audio files copied into the app sandbox. This path needs no MusicKit
/// authorization: it covers songs the user actually owns on the phone.
@MainActor
final class LocalMusicLibrary: ObservableObject {
    static let shared = LocalMusicLibrary()
    static let allowedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    @Published private(set) var tracks: [LocalTrack] = []
    @Published private(set) var currentTrackId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var positionSec: Double = 0
    @Published private(set) var lastError: String?
    var prefersShuffle = false

    private var player: AVAudioPlayer?
    private var audioLease: UUID?
    private var ticker: Timer?
    private let fm = FileManager.default
    private var didBootstrap = false
    private let audioDelegate = LocalAudioDelegate()

    private init() {
        audioDelegate.onFinish = { [weak self] in
            self?.handleFinished()
        }
        audioDelegate.onError = { [weak self] error in
            self?.isPlaying = false
            self?.lastError = error?.localizedDescription ?? "这个音频文件无法解码"
        }
        bootstrap()
    }

    var currentTrack: LocalTrack? {
        guard let currentTrackId else { return nil }
        return tracks.first { $0.id == currentTrackId }
    }

    var hasActivePlayback: Bool {
        player != nil
    }

    // MARK: - Library

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        try? fm.createDirectory(at: LocalMusicPaths.media, withIntermediateDirectories: true)
        loadIndex()
        Task { await self.scanForNewFiles() }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: LocalMusicPaths.index),
              let decoded = try? JSONDecoder().decode([LocalTrack].self, from: data) else {
            tracks = []
            return
        }
        tracks = decoded.filter { fm.fileExists(atPath: LocalMusicPaths.media.appendingPathComponent($0.fileName).path) }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: LocalMusicPaths.index, options: .atomic)
    }

    /// Picks up files dropped into the app Documents/Music folder via Finder.
    func scanForNewFiles() async {
        let known = Set(tracks.map(\.fileName))
        guard let names = try? fm.contentsOfDirectory(atPath: LocalMusicPaths.media.path) else { return }
        var added: [LocalTrack] = []
        for name in names.sorted() {
            guard !name.hasPrefix("."), !known.contains(name) else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            guard Self.allowedExtensions.contains(ext) else { continue }
            let url = LocalMusicPaths.media.appendingPathComponent(name)
            let meta = await Self.readMetadata(url)
            added.append(LocalTrack(
                id: "local:\(UUID().uuidString)",
                title: meta.title ?? (name as NSString).deletingPathExtension,
                artist: meta.artist ?? "本机文件",
                fileName: name,
                durationSec: meta.duration,
                addedAt: Date()
            ))
        }
        guard !added.isEmpty else { return }
        tracks.append(contentsOf: added)
        saveIndex()
    }

    @discardableResult
    func importFiles(_ urls: [URL]) async -> (imported: Int, failures: [String]) {
        try? fm.createDirectory(at: LocalMusicPaths.media, withIntermediateDirectories: true)
        var imported = 0
        var failures: [String] = []

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            guard Self.allowedExtensions.contains(ext) else {
                failures.append("\(url.lastPathComponent)：暂不支持该格式")
                continue
            }
            var destination = LocalMusicPaths.media.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let suffix = UUID().uuidString.prefix(4).lowercased()
                destination = LocalMusicPaths.media.appendingPathComponent("\(base)-\(suffix).\(ext)")
            }
            do {
                try fm.copyItem(at: url, to: destination)
                let meta = await Self.readMetadata(destination)
                tracks.append(LocalTrack(
                    id: "local:\(UUID().uuidString)",
                    title: meta.title ?? url.deletingPathExtension().lastPathComponent,
                    artist: meta.artist ?? "本机文件",
                    fileName: destination.lastPathComponent,
                    durationSec: meta.duration,
                    addedAt: Date()
                ))
                imported += 1
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if imported > 0 { saveIndex() }
        lastError = failures.first
        return (imported, failures)
    }

    func delete(id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let track = tracks[index]
        if currentTrackId == id { stop() }
        try? fm.removeItem(at: LocalMusicPaths.media.appendingPathComponent(track.fileName))
        tracks.remove(at: index)
        saveIndex()
    }

    // MARK: - Playback

    func play(id: String) throws {
        guard let track = tracks.first(where: { $0.id == id }) else {
            throw NSError(domain: "LocalMusic", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到这首本机歌曲，请重新导入"])
        }
        try play(track: track)
    }

    private func play(track: LocalTrack) throws {
        let url = LocalMusicPaths.media.appendingPathComponent(track.fileName)
        guard fm.fileExists(atPath: url.path) else {
            throw NSError(domain: "LocalMusic", code: 404, userInfo: [NSLocalizedDescriptionKey: "歌曲文件已不存在，请重新导入"])
        }
        stopTicker()
        player?.stop()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = audioDelegate
        audio.prepareToPlay()
        audioLease = try AudioSessionCoordinator.shared.acquire(.music) { [weak self] in self?.pause() }
        guard audio.play() else {
            AudioSessionCoordinator.shared.release(audioLease)
            audioLease = nil
            throw NSError(domain: "LocalMusic", code: 500, userInfo: [NSLocalizedDescriptionKey: "系统没能开始播放这首歌"])
        }
        player = audio
        currentTrackId = track.id
        isPlaying = true
        positionSec = 0
        lastError = nil
        startTicker()
    }

    func pause() {
        player?.pause()
        AudioSessionCoordinator.shared.release(audioLease)
        audioLease = nil
        isPlaying = false
    }

    func resume() throws {
        guard let player else {
            throw NSError(domain: "LocalMusic", code: 409, userInfo: [NSLocalizedDescriptionKey: "还没有选中的本机歌曲"])
        }
        audioLease = try AudioSessionCoordinator.shared.acquire(.music) { [weak self] in self?.pause() }
        guard player.play() else {
            AudioSessionCoordinator.shared.release(audioLease)
            audioLease = nil
            throw NSError(domain: "LocalMusic", code: 500, userInfo: [NSLocalizedDescriptionKey: "继续播放失败"])
        }
        isPlaying = true
        startTicker()
    }

    func stop() {
        AudioSessionCoordinator.shared.release(audioLease)
        audioLease = nil
        stopTicker()
        player?.stop()
        player = nil
        currentTrackId = nil
        isPlaying = false
        positionSec = 0
    }

    @discardableResult
    func skip(direction: String) -> Bool {
        guard let currentTrackId, let index = tracks.firstIndex(where: { $0.id == currentTrackId }) else {
            return false
        }
        if direction == "previous" {
            let target = index - 1
            guard tracks.indices.contains(target) else { return false }
            try? play(track: tracks[target])
            return true
        }
        if prefersShuffle, tracks.count > 1 {
            try? play(track: tracks[randomIndex(excluding: index)])
            return true
        }
        let target = index + 1
        guard tracks.indices.contains(target) else { return false }
        try? play(track: tracks[target])
        return true
    }

    private func randomIndex(excluding index: Int) -> Int {
        let pool = tracks.indices.filter { $0 != index }
        return pool.randomElement() ?? index
    }

    func snapshot() -> [String: Any] {
        var payload: [String: Any] = [
            "sessionId": "local",
            "state": isPlaying ? "playing" : (player == nil ? "stopped" : "paused"),
            "positionSec": positionSec,
            "queueLength": tracks.count,
            "audioOutput": isPlaying,
            "source": "local",
            "simulated": false
        ]
        if let track = currentTrack {
            payload["track"] = [
                "trackId": track.id,
                "title": track.title,
                "artist": track.artist,
                "album": "本机文件",
                "durationSec": track.durationSec
            ]
        } else {
            payload["track"] = NSNull()
        }
        return payload
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.positionSec = self.player?.currentTime ?? 0
                if let player = self.player, !player.isPlaying, self.isPlaying {
                    self.isPlaying = false
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func handleFinished() {
        isPlaying = false
        positionSec = 0
        guard let currentTrackId, let index = tracks.firstIndex(where: { $0.id == currentTrackId }) else {
            stopTicker()
            return
        }
        if prefersShuffle, tracks.count > 1 {
            try? play(track: tracks[randomIndex(excluding: index)])
            return
        }
        guard tracks.indices.contains(index + 1) else {
            stopTicker()
            AudioSessionCoordinator.shared.release(audioLease)
            audioLease = nil
            return
        }
        try? play(track: tracks[index + 1])
    }

    nonisolated private static func readMetadata(_ url: URL) async -> (title: String?, artist: String?, duration: Double) {
        let asset = AVURLAsset(url: url)
        var title: String?
        var artist: String?
        var duration: Double = 0
        if let value = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(value)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle {
                    title = try? await item.load(.stringValue)
                } else if key == .commonKeyArtist {
                    artist = try? await item.load(.stringValue)
                }
            }
        }
        return (title?.trimmingCharacters(in: .whitespacesAndNewlines), artist?.trimmingCharacters(in: .whitespacesAndNewlines), duration)
    }
}

private final class LocalAudioDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    var onError: ((Error?) -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onError?(error)
    }
}

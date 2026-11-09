import Foundation
import MusicKit

@MainActor
final class MusicExecutor {
    private let player = ApplicationMusicPlayer.shared
    private var songs: [String: Song] = [:]
    private var queue: [Song] = []
    private var currentIndex = 0
    private var sessionId: String?
    private var activeSource = "musickit"

    func search(arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = (arguments.optionalString("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min(max(arguments.optionalInt("limit") ?? 10, 1), 25)
        var payloadTracks: [JSONValue] = []

        let localMatches = LocalMusicLibrary.shared.tracks.filter { track in
            query.isEmpty
                || track.title.localizedCaseInsensitiveContains(query)
                || track.artist.localizedCaseInsensitiveContains(query)
        }
        let localSelected = Array(localMatches.prefix(limit))
        payloadTracks.append(contentsOf: localSelected.map(localTrackJSON))

        var systemCount = 0
        var systemUnavailable: String?
        do {
            var request = MusicLibraryRequest<Song>()
            request.limit = 100
            if !query.isEmpty {
                request.filter(text: query)
            }
            let response = try await request.response()
            var items = Array(response.items)
            if let artist = arguments.optionalString("artist"), !artist.isEmpty {
                items = items.filter { $0.artistName.localizedCaseInsensitiveContains(artist) }
            }
            let selected = Array(items.prefix(limit))
            for song in selected {
                songs[song.id.rawValue] = song
            }
            systemCount = selected.count
            payloadTracks.append(contentsOf: selected.map(trackJSON))
        } catch {
            systemUnavailable = error.localizedDescription
        }

        let note: String
        if payloadTracks.isEmpty {
            if let systemUnavailable {
                note = "系统音乐库暂不可用（\(systemUnavailable)）。可以点“导入音乐文件”直接添加手机里的歌曲。"
            } else {
                note = "系统音乐库为空。第三方 App 里下载的歌曲无法直接读取，请点“导入音乐文件”。"
            }
        } else {
            note = "本机文件 \(localSelected.count) 首，系统音乐库 \(systemCount) 首"
        }

        return .object([
            "tracks": .array(payloadTracks),
            "total": .number(Double(payloadTracks.count)),
            "library": .string("mixed"),
            "localCount": .number(Double(localSelected.count)),
            "systemCount": .number(Double(systemCount)),
            "note": .string(note),
            "source": .string("mixed"),
            "simulated": .bool(false)
        ])
    }

    func play(arguments: [String: JSONValue]) async throws -> JSONValue {
        let trackId = try arguments.requiredString("trackId")

        if trackId.hasPrefix("local:") {
            if case .playing = player.state.playbackStatus {
                player.pause()
            }
            try LocalMusicLibrary.shared.play(id: trackId)
            activeSource = "local"
            queue = []
            if sessionId == nil {
                sessionId = "ms_\(UUID().uuidString.prefix(8))"
            }
            return localPlaybackJSON()
        }

        guard let song = songs[trackId] else {
            throw ToolExecutionError(code: "unknown_track", message: "曲目引用不存在或已过期，请重新选择")
        }

        LocalMusicLibrary.shared.stop()
        activeSource = "musickit"

        if arguments.optionalString("queueIntent") == "append", !queue.isEmpty {
            queue.append(song)
            let start = queue.indices.contains(currentIndex) ? queue[currentIndex] : song
            player.queue = ApplicationMusicPlayer.Queue(for: queue, startingAt: start)
        } else {
            queue = [song]
            currentIndex = 0
            player.queue = [song]
        }

        try await player.prepareToPlay()
        try await player.play()
        if sessionId == nil {
            sessionId = "ms_\(UUID().uuidString.prefix(8))"
        }
        return playbackJSON()
    }

    func pause(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            guard LocalMusicLibrary.shared.hasActivePlayback else {
                throw ToolExecutionError(code: "no_active_playback", message: "当前没有正在播放的音乐")
            }
            LocalMusicLibrary.shared.pause()
            return localPlaybackJSON()
        }
        guard case .playing = player.state.playbackStatus else {
            throw ToolExecutionError(code: "no_active_playback", message: "当前没有正在播放的音乐")
        }
        player.pause()
        return playbackJSON()
    }

    func resume(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            guard LocalMusicLibrary.shared.hasActivePlayback else {
                throw ToolExecutionError(code: "no_paused_playback", message: "当前没有可继续的播放，需要先选曲")
            }
            try LocalMusicLibrary.shared.resume()
            return localPlaybackJSON()
        }
        guard case .paused = player.state.playbackStatus else {
            throw ToolExecutionError(code: "no_paused_playback", message: "当前没有可继续的播放，需要先选曲")
        }
        try await player.play()
        return playbackJSON()
    }

    func skip(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            let moved = LocalMusicLibrary.shared.skip(direction: arguments.optionalString("direction") ?? "next")
            return localPlaybackJSON(atBoundary: !moved)
        }
        guard !queue.isEmpty else {
            throw ToolExecutionError(code: "no_active_playback", message: "当前没有可切换的播放队列")
        }

        if arguments.optionalString("direction") == "previous" {
            if currentIndex == 0 {
                return playbackJSON(atBoundary: true)
            }
            try await player.skipToPreviousEntry()
            currentIndex = max(0, currentIndex - 1)
        } else {
            if currentIndex >= queue.count - 1 {
                return playbackJSON(atBoundary: true)
            }
            try await player.skipToNextEntry()
            currentIndex = min(queue.count - 1, currentIndex + 1)
        }
        return playbackJSON()
    }

    func playbackState(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            return localPlaybackJSON()
        }
        return playbackJSON()
    }

    private func localTrackJSON(_ track: LocalTrack) -> JSONValue {
        .object([
            "trackId": .string(track.id),
            "title": .string(track.title),
            "artist": .string(track.artist),
            "album": .string("本机文件"),
            "durationSec": .number(track.durationSec),
            "artworkURL": .null,
            "source": .string("local")
        ])
    }

    private func localPlaybackJSON(atBoundary: Bool = false) -> JSONValue {
        let library = LocalMusicLibrary.shared
        var payload: [String: JSONValue] = [
            "sessionId": .string(sessionId ?? "local"),
            "state": .string(library.isPlaying ? "playing" : (library.hasActivePlayback ? "paused" : "stopped")),
            "track": library.currentTrack.map { localTrackJSON($0) } ?? .null,
            "positionSec": .number(library.positionSec),
            "queueLength": .number(Double(library.tracks.count)),
            "audioOutput": .bool(library.isPlaying),
            "source": .string("local"),
            "simulated": .bool(false)
        ]
        if atBoundary {
            payload["atBoundary"] = .bool(true)
        }
        return .object(payload)
    }

    private func trackJSON(_ song: Song) -> JSONValue {
        let artworkURL = song.artwork?.url(width: 300, height: 300)
        return .object([
            "trackId": .string(song.id.rawValue),
            "title": .string(song.title),
            "artist": .string(song.artistName),
            "album": .string(song.albumTitle ?? ""),
            "durationSec": .number(song.duration ?? 0),
            "artworkURL": artworkURL.map { JSONValue.string($0.absoluteString) } ?? .null,
            "source": .string("musickit")
        ])
    }

    private func playbackJSON(atBoundary: Bool = false) -> JSONValue {
        let state: String
        switch player.state.playbackStatus {
        case .playing:
            state = "playing"
        case .paused:
            state = "paused"
        case .stopped:
            state = "stopped"
        default:
            state = String(describing: player.state.playbackStatus)
        }

        var payload: [String: JSONValue] = [
            "sessionId": sessionId.map { JSONValue.string($0) } ?? .null,
            "state": .string(state),
            "track": queue.indices.contains(currentIndex) ? trackJSON(queue[currentIndex]) : .null,
            "positionSec": .number(player.playbackTime),
            "queueLength": .number(Double(queue.count)),
            "audioOutput": .bool(state == "playing"),
            "source": .string("musickit"),
            "simulated": .bool(false)
        ]
        if atBoundary {
            payload["atBoundary"] = .bool(true)
        }
        return .object(payload)
    }
}

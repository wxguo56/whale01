import Foundation
import MusicKit

@MainActor
final class MusicExecutor {
    private let player = ApplicationMusicPlayer.shared
    private var songs: [String: Song] = [:]
    private var queue: [Song] = []
    private var currentIndex = 0
    private var sessionId: String?

    func search(arguments: [String: JSONValue]) async throws -> JSONValue {
        var request = MusicLibraryRequest<Song>()
        request.limit = 100
        if let query = arguments.optionalString("query"), !query.isEmpty {
            request.filter(text: query)
        }

        let response = try await request.response()
        var items = Array(response.items)
        if let artist = arguments.optionalString("artist"), !artist.isEmpty {
            items = items.filter { $0.artistName.localizedCaseInsensitiveContains(artist) }
        }

        let limit = min(max(arguments.optionalInt("limit") ?? 10, 1), 25)
        let selected = Array(items.prefix(limit))
        for song in selected {
            songs[song.id.rawValue] = song
        }

        return .object([
            "tracks": .array(selected.map(trackJSON)),
            "total": .number(Double(selected.count)),
            "library": .string("musickit"),
            "note": .string(selected.isEmpty ? "音乐库没有匹配曲目" : "来自用户已授权的音乐库"),
            "source": .string("musickit"),
            "simulated": .bool(false)
        ])
    }

    func play(arguments: [String: JSONValue]) async throws -> JSONValue {
        let trackId = try arguments.requiredString("trackId")
        guard let song = songs[trackId] else {
            throw ToolExecutionError(code: "unknown_track", message: "曲目引用不存在或已过期，请重新选择")
        }

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
        guard case .playing = player.state.playbackStatus else {
            throw ToolExecutionError(code: "no_active_playback", message: "当前没有正在播放的音乐")
        }
        player.pause()
        return playbackJSON()
    }

    func resume(arguments: [String: JSONValue]) async throws -> JSONValue {
        guard case .paused = player.state.playbackStatus else {
            throw ToolExecutionError(code: "no_paused_playback", message: "当前没有可继续的播放，需要先选曲")
        }
        try await player.play()
        return playbackJSON()
    }

    func skip(arguments: [String: JSONValue]) async throws -> JSONValue {
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
        playbackJSON()
    }

    private func trackJSON(_ song: Song) -> JSONValue {
        let artworkURL = song.artwork?.url(width: 300, height: 300)
        return .object([
            "trackId": .string(song.id.rawValue),
            "title": .string(song.title),
            "artist": .string(song.artistName),
            "album": .string(song.albumTitle ?? ""),
            "durationSec": .number(song.duration ?? 0),
            "artworkURL": artworkURL.map { JSONValue.string($0.absoluteString) } ?? .null
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

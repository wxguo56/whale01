import Foundation
import UIKit

@MainActor
final class MusicExecutor {
    private let systemLibrary = SystemMusicLibrary.shared
    private var sessionId: String?
    private var activeSource = "system"

    func search(arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = (arguments.optionalString("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (arguments.optionalString("artist") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min(max(arguments.optionalInt("limit") ?? 10, 1), 25)

        let localMatches = LocalMusicLibrary.shared.tracks.filter { track in
            let matchesQuery = query.isEmpty
                || track.title.localizedCaseInsensitiveContains(query)
                || track.artist.localizedCaseInsensitiveContains(query)
            let matchesArtist = artist.isEmpty || track.artist.localizedCaseInsensitiveContains(artist)
            return matchesQuery && matchesArtist
        }
        let localSelected = Array(localMatches.prefix(limit))

        let systemResult = await systemLibrary.search(
            query: query,
            artist: artist,
            trackLimit: max(0, limit - localSelected.count),
            albumLimit: 24
        )

        var payloadTracks: [JSONValue] = localSelected.map(localTrackJSON)
        payloadTracks.append(contentsOf: systemResult.tracks.map(systemTrackJSON))

        let note: String
        if !systemResult.authorized {
            note = "系统音乐库权限是「\(systemLibrary.authorizationText)」。请允许访问「媒体与 Apple Music」；导入的本机文件仍可播放。"
        } else if payloadTracks.isEmpty && systemResult.albums.isEmpty {
            if query.isEmpty {
                note = "系统音乐资料库里没有找到歌曲或专辑。可以导入自己的音频文件，或打开已登录的网易云音乐。"
            } else {
                note = "系统音乐资料库里没有找到「\(query)」。换一个关键词试试。"
            }
        } else {
            note = "系统资料库 \(systemResult.tracks.count) 首 · \(systemResult.albums.count) 张专辑；本机文件 \(localSelected.count) 首"
        }

        return .object([
            "tracks": .array(payloadTracks),
            "albums": .array(systemResult.albums.map(albumJSON)),
            "total": .number(Double(payloadTracks.count)),
            "albumCount": .number(Double(systemResult.albums.count)),
            "libraryAuthorized": .bool(systemResult.authorized),
            "library": .string("mixed"),
            "localCount": .number(Double(localSelected.count)),
            "systemCount": .number(Double(systemResult.tracks.count)),
            "note": .string(note),
            "source": .string("mixed"),
            "simulated": .bool(false)
        ])
    }

    func play(arguments: [String: JSONValue]) async throws -> JSONValue {
        if let albumId = arguments.optionalString("albumId"), !albumId.isEmpty {
            return try await playAlbum(albumId: albumId)
        }

        let trackId = try arguments.requiredString("trackId")
        if trackId.hasPrefix("album:") {
            return try await playAlbum(albumId: trackId)
        }
        if trackId.hasPrefix("local:") {
            if systemLibrary.hasActivePlayback {
                try? systemLibrary.pause()
            }
            try LocalMusicLibrary.shared.play(id: trackId)
            activeSource = "local"
            ensureSession()
            return localPlaybackJSON()
        }

        LocalMusicLibrary.shared.stop()
        activeSource = "system"
        try await systemLibrary.playTrack(trackId: trackId)
        ensureSession()
        return systemPlaybackJSON()
    }

    func playAlbum(albumId: String) async throws -> JSONValue {
        if LocalMusicLibrary.shared.hasActivePlayback {
            LocalMusicLibrary.shared.stop()
        }
        activeSource = "system"
        try await systemLibrary.playAlbum(albumId: albumId)
        ensureSession()
        return systemPlaybackJSON()
    }

    func openNetEase(arguments: [String: JSONValue]) async throws -> JSONValue {
        for candidate in ["orpheus://", "neteasecloudmusic://"] {
            guard let url = URL(string: candidate) else { continue }
            if await open(url) {
                return .object([
                    "state": .string("opened_external_app"),
                    "source": .string("netease"),
                    "note": .string("已打开网易云音乐 App；鲸鱼没有读取账号、歌库或代替它播放"),
                    "simulated": .bool(false)
                ])
            }
        }
        throw ToolExecutionError(code: "netease_not_installed", message: "没有检测到已安装的网易云音乐 App，请先安装并登录")
    }

    func pause(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            guard LocalMusicLibrary.shared.hasActivePlayback else {
                throw ToolExecutionError(code: "no_active_playback", message: "当前没有正在播放的音乐")
            }
            LocalMusicLibrary.shared.pause()
            return localPlaybackJSON()
        }
        do {
            try systemLibrary.pause()
        } catch {
            throw ToolExecutionError(code: "no_active_playback", message: error.localizedDescription)
        }
        return systemPlaybackJSON()
    }

    func resume(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            guard LocalMusicLibrary.shared.hasActivePlayback else {
                throw ToolExecutionError(code: "no_paused_playback", message: "当前没有可继续的播放，需要先选曲")
            }
            try LocalMusicLibrary.shared.resume()
            return localPlaybackJSON()
        }
        do {
            try systemLibrary.resume()
        } catch {
            throw ToolExecutionError(code: "no_paused_playback", message: error.localizedDescription)
        }
        return systemPlaybackJSON()
    }

    func skip(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            let moved = LocalMusicLibrary.shared.skip(direction: arguments.optionalString("direction") ?? "next")
            return localPlaybackJSON(atBoundary: !moved)
        }

        do {
            let moved = try await systemLibrary.skip(direction: arguments.optionalString("direction") ?? "next")
            return systemPlaybackJSON(atBoundary: !moved)
        } catch {
            throw ToolExecutionError(code: "no_active_playback", message: error.localizedDescription)
        }
    }

    func playbackState(arguments: [String: JSONValue]) async throws -> JSONValue {
        if activeSource == "local" {
            return localPlaybackJSON()
        }
        return systemPlaybackJSON()
    }

    private func ensureSession() {
        if sessionId == nil {
            sessionId = "ms_\(UUID().uuidString.prefix(8))"
        }
    }

    private func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    private func localTrackJSON(_ track: LocalTrack) -> JSONValue {
        .object([
            "trackId": .string(track.id),
            "title": .string(track.title),
            "artist": .string(track.artist),
            "album": .string("本机文件"),
            "albumId": .null,
            "durationSec": .number(track.durationSec),
            "artworkURL": .null,
            "source": .string("local")
        ])
    }

    private func systemTrackJSON(_ track: SystemMusicTrack) -> JSONValue {
        .object([
            "trackId": .string(track.trackId),
            "title": .string(track.title),
            "artist": .string(track.artist),
            "album": .string(track.album),
            "albumId": .string(track.albumId),
            "durationSec": .number(track.durationSec),
            "artworkURL": .null,
            "source": .string("system")
        ])
    }

    private func albumJSON(_ album: SystemMusicAlbum) -> JSONValue {
        .object([
            "albumId": .string(album.albumId),
            "title": .string(album.title),
            "artist": .string(album.artist),
            "trackCount": .number(Double(album.trackCount)),
            "artworkURL": .null,
            "source": .string("system")
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

    private func systemPlaybackJSON(atBoundary: Bool = false) -> JSONValue {
        let snapshot = systemLibrary.snapshot()
        var payload: [String: JSONValue] = [
            "sessionId": sessionId.map { JSONValue.string($0) } ?? .null,
            "state": .string(snapshot.state),
            "track": snapshot.track.map(systemTrackJSON) ?? .null,
            "positionSec": .number(snapshot.positionSec),
            "queueLength": .number(Double(snapshot.queueLength)),
            "queueIndex": snapshot.queueIndex.map { JSONValue.number(Double($0)) } ?? .null,
            "audioOutput": .bool(snapshot.state == "playing"),
            "source": .string("system"),
            "simulated": .bool(false)
        ]
        if atBoundary {
            payload["atBoundary"] = .bool(true)
        }
        return .object(payload)
    }
}

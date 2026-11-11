import Foundation
import MediaPlayer
import UIKit

enum SystemMusicError: LocalizedError {
    case notAuthorized
    case albumNotFound
    case trackNotFound
    case playbackNotStarted
    case noActivePlayback
    case noPausedPlayback

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有「媒体与 Apple Music」权限，无法读取系统音乐资料库。请到系统设置开启后重试。"
        case .albumNotFound:
            return "没有在系统音乐资料库里找到这张专辑，请重新读取后再选。"
        case .trackNotFound:
            return "没有在系统音乐资料库里找到这首歌，请重新读取后再选。"
        case .playbackNotStarted:
            return "系统音乐播放器没有开始播放。请确认歌曲已下载，且当前账号可以播放这首歌曲。"
        case .noActivePlayback:
            return "当前没有正在播放的音乐。"
        case .noPausedPlayback:
            return "当前没有暂停中的音乐，需要先选一张专辑或一首歌。"
        }
    }
}

struct SystemMusicAlbum {
    let albumId: String
    let title: String
    let artist: String
    let trackCount: Int
    let artwork: UIImage?
}

struct SystemMusicTrack {
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    let durationSec: Double
    let artwork: UIImage?
}

struct SystemMusicSearchResult {
    let tracks: [SystemMusicTrack]
    let albums: [SystemMusicAlbum]
    let authorized: Bool
}

struct SystemMusicSnapshot {
    let state: String
    let track: SystemMusicTrack?
    let positionSec: Double
    let queueLength: Int
    let queueIndex: Int?
}

@MainActor
final class SystemMusicLibrary {
    static let shared = SystemMusicLibrary()

    private let player = MPMusicPlayerController.applicationMusicPlayer
    private var albumItems: [String: [MPMediaItem]] = [:]
    private var albumMetadata: [String: SystemMusicAlbum] = [:]
    private var knownTracks: [String: MPMediaItem] = [:]
    private var queue: [MPMediaItem] = []

    private init() {}

    var authorizationText: String {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受系统限制"
        case .notDetermined:
            return "尚未授权"
        @unknown default:
            return "状态未知"
        }
    }

    var hasActivePlayback: Bool {
        player.playbackState != .stopped || player.nowPlayingItem != nil
    }

    func requestAccess() async -> Bool {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    func search(query: String?, artist: String?, trackLimit: Int, albumLimit: Int) async -> SystemMusicSearchResult {
        let authorized = await requestAccess()
        guard authorized else {
            return SystemMusicSearchResult(tracks: [], albums: [], authorized: false)
        }

        let queryText = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artistText = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let allSongs = MPMediaQuery.songs().items ?? []
        let songMatches = allSongs.filter { item in
            let title = item.title ?? ""
            let itemArtist = item.artist ?? item.albumArtist ?? ""
            let album = item.albumTitle ?? ""
            let matchesQuery = queryText.isEmpty
                || title.localizedCaseInsensitiveContains(queryText)
                || itemArtist.localizedCaseInsensitiveContains(queryText)
                || album.localizedCaseInsensitiveContains(queryText)
            let matchesArtist = artistText.isEmpty
                || itemArtist.localizedCaseInsensitiveContains(artistText)
                || (item.albumArtist ?? "").localizedCaseInsensitiveContains(artistText)
            return matchesQuery && matchesArtist
        }

        var tracks: [SystemMusicTrack] = []
        for item in songMatches.prefix(max(0, trackLimit)) {
            tracks.append(track(from: item))
        }

        var candidates: [(id: String, title: String, artist: String, items: [MPMediaItem], representative: MPMediaItem)] = []
        for collection in MPMediaQuery.albums().collections ?? [] {
            guard let representative = collection.representativeItem else { continue }
            let id = albumId(for: representative)
            let title = representative.albumTitle ?? "未知专辑"
            let albumArtist = representative.albumArtist ?? representative.artist ?? "未知艺人"
            let matchesQuery = queryText.isEmpty
                || title.localizedCaseInsensitiveContains(queryText)
                || albumArtist.localizedCaseInsensitiveContains(queryText)
            let matchesArtist = artistText.isEmpty
                || albumArtist.localizedCaseInsensitiveContains(artistText)
            guard matchesQuery && matchesArtist else { continue }
            candidates.append((id, title, albumArtist, collection.items, representative))
        }

        candidates.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        var albums: [SystemMusicAlbum] = []
        for candidate in candidates.prefix(max(0, albumLimit)) {
            let metadata = SystemMusicAlbum(
                albumId: candidate.id,
                title: candidate.title,
                artist: candidate.artist,
                trackCount: candidate.items.count,
                artwork: candidate.representative.artwork?.image(at: CGSize(width: 360, height: 360))
            )
            albumItems[candidate.id] = candidate.items
            albumMetadata[candidate.id] = metadata
            albums.append(metadata)
        }
        return SystemMusicSearchResult(
            tracks: tracks,
            albums: albums,
            authorized: true
        )
    }

    func playAlbum(albumId: String) async throws {
        guard await requestAccess() else { throw SystemMusicError.notAuthorized }
        let items = albumItems[albumId] ?? reloadAlbumItems(albumId)
        guard let items, !items.isEmpty else { throw SystemMusicError.albumNotFound }

        queue = items
        player.setQueue(with: MPMediaItemCollection(items: items))
        try await player.prepareToPlay()
        player.play()
        try await Task.sleep(nanoseconds: 900_000_000)

        if player.playbackState == .stopped && player.nowPlayingItem == nil {
            throw SystemMusicError.playbackNotStarted
        }
    }

    func playTrack(trackId: String) async throws {
        guard await requestAccess() else { throw SystemMusicError.notAuthorized }
        guard let item = knownTracks[trackId] ?? findTrack(trackId) else {
            throw SystemMusicError.trackNotFound
        }

        queue = [item]
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        try await player.prepareToPlay()
        player.play()
        try await Task.sleep(nanoseconds: 900_000_000)

        if player.playbackState == .stopped && player.nowPlayingItem == nil {
            throw SystemMusicError.playbackNotStarted
        }
    }

    func setShuffle(_ enabled: Bool) {
        player.shuffleMode = enabled ? .songs : .off
    }

    func pause() throws {
        guard player.playbackState == .playing else { throw SystemMusicError.noActivePlayback }
        player.pause()
    }

    func resume() throws {
        let paused = player.playbackState == .paused || player.playbackState == .interrupted
        guard paused else { throw SystemMusicError.noPausedPlayback }
        player.play()
    }

    @discardableResult
    func skip(direction: String) async throws -> Bool {
        guard !queue.isEmpty else { throw SystemMusicError.noActivePlayback }
        let currentIndex = indexOfNowPlaying()

        if direction == "previous" {
            if let currentIndex, currentIndex <= 0 { return false }
            player.skipToPreviousItem()
        } else {
            if let currentIndex, currentIndex >= queue.count - 1 { return false }
            player.skipToNextItem()
        }
        try await Task.sleep(nanoseconds: 350_000_000)
        return true
    }

    func snapshot() -> SystemMusicSnapshot {
        let item = player.nowPlayingItem
        let state: String
        switch player.playbackState {
        case .playing, .seekingForward, .seekingBackward:
            state = "playing"
        case .paused, .interrupted:
            state = "paused"
        default:
            state = "stopped"
        }

        let rawPosition = player.currentPlaybackTime
        let position = rawPosition.isFinite && rawPosition > 0 ? rawPosition : 0
        return SystemMusicSnapshot(
            state: state,
            track: item.map { track(from: $0) },
            positionSec: position,
            queueLength: queue.count,
            queueIndex: indexOfNowPlaying()
        )
    }

    func artwork(forAlbumId albumId: String) -> UIImage? {
        albumMetadata[albumId]?.artwork
    }

    func artwork(forTrackId trackId: String) -> UIImage? {
        knownTracks[trackId]?.artwork?.image(at: CGSize(width: 160, height: 160))
    }

    private func track(from item: MPMediaItem) -> SystemMusicTrack {
        let id = trackId(for: item)
        knownTracks[id] = item
        return SystemMusicTrack(
            trackId: id,
            title: item.title ?? "未知歌曲",
            artist: item.artist ?? item.albumArtist ?? "未知艺人",
            album: item.albumTitle ?? "未知专辑",
            albumId: albumId(for: item),
            durationSec: item.playbackDuration,
            artwork: item.artwork?.image(at: CGSize(width: 160, height: 160))
        )
    }

    private func albumId(for item: MPMediaItem) -> String {
        if item.albumPersistentID != 0 {
            return "album:\(item.albumPersistentID)"
        }
        let seed = "\(item.albumTitle ?? "")\u{1f}\(item.albumArtist ?? item.artist ?? "")"
        return "album:g\(stableToken(seed))"
    }

    private func trackId(for item: MPMediaItem) -> String {
        if item.persistentID != 0 {
            return "library:\(item.persistentID)"
        }
        let seed = "\(item.title ?? "")\u{1f}\(item.albumTitle ?? "")\u{1f}\(item.artist ?? "")"
        return "library:g\(stableToken(seed))"
    }

    private func stableToken(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = (hash &* 33) ^ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func reloadAlbumItems(_ albumId: String) -> [MPMediaItem]? {
        for collection in MPMediaQuery.albums().collections ?? [] {
            guard let representative = collection.representativeItem else { continue }
            guard self.albumId(for: representative) == albumId else { continue }
            let metadata = SystemMusicAlbum(
                albumId: albumId,
                title: representative.albumTitle ?? "未知专辑",
                artist: representative.albumArtist ?? representative.artist ?? "未知艺人",
                trackCount: collection.items.count,
                artwork: representative.artwork?.image(at: CGSize(width: 360, height: 360))
            )
            albumItems[albumId] = collection.items
            albumMetadata[albumId] = metadata
            return collection.items
        }
        return nil
    }

    private func findTrack(_ trackId: String) -> MPMediaItem? {
        for item in MPMediaQuery.songs().items ?? [] where self.trackId(for: item) == trackId {
            knownTracks[trackId] = item
            return item
        }
        return nil
    }

    private func indexOfNowPlaying() -> Int? {
        guard let nowPlaying = player.nowPlayingItem else { return nil }
        if nowPlaying.persistentID != 0 {
            return queue.firstIndex { $0.persistentID == nowPlaying.persistentID }
        }
        return queue.firstIndex {
            $0.title == nowPlaying.title
                && $0.albumTitle == nowPlaying.albumTitle
                && $0.artist == nowPlaying.artist
        }
    }
}

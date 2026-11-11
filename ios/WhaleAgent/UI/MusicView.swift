import Combine
import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var model: AppModel
    var showsClose = false

    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showSourceInfo = false
    @State private var libraryExpanded = false
    @State private var browsedAlbumId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    searchField
                    playerCard
                    librarySection
                    neteaseCard
                    if model.permissionsSnapshot["music"] != "granted" {
                        permissionCard
                    }
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(WhaleTheme.pageGradient)
            .navigationTitle("音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .task { await model.musicAppeared() }
            .refreshable {
                model.refreshPermissions()
                await model.loadMusicLibrary()
                await model.refreshPlayback()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await model.importLocalMusic(from: urls) }
            }
            .alert("音乐从哪来", isPresented: $showSourceInfo) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("系统「音乐」资料库里的歌曲和专辑可以直接读取和播放。网易云等第三方 App 的账号、歌单和离线缓存位于各自沙盒，iOS 不允许鲸鱼读取或代替它播放；鲸鱼只能打开已登录的网易云 App。")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WhaleTheme.muted)
            TextField("搜索歌曲、艺人或专辑", text: $model.musicQuery)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await model.loadMusicLibrary() }
                }
            if !model.musicQuery.isEmpty {
                Button {
                    model.musicQuery = ""
                    Task { await model.loadMusicLibrary() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private var playerCard: some View {
        VStack(spacing: 16) {
            VinylDisc(
                artwork: displayArtwork,
                title: displayTitle,
                isPlaying: model.playback.isPlaying,
                palette: albumColors(for: displayTitle)
            )
            .frame(width: 246, height: 246)
            .contentShape(Circle())
            .gesture(albumSwipe)

            VStack(spacing: 5) {
                Text(displayTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(displaySubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }

            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WhaleTheme.line)
                        Capsule()
                            .fill(WhaleTheme.accent)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(timeText(model.playback.positionSec))
                    Spacer()
                    Text(timeText(model.playback.track?.durationSec ?? 0))
                }
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 34) {
                Button {
                    Task { await model.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(width: 52, height: 44)
                }
                .disabled(model.isMusicBusy)

                Button {
                    Task { await model.togglePlayback() }
                } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(WhaleTheme.accent, in: Circle())
                }
                .disabled(model.isMusicBusy)

                Button {
                    model.toggleMusicPlayMode()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: model.musicPlayMode.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(model.musicPlayMode.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(WhaleTheme.ink)
                    .frame(width: 62, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(model.musicPlayMode.title)
            }

            Text("左右滑动唱片切换专辑")
                .font(.system(size: 10))
                .foregroundStyle(WhaleTheme.muted.opacity(0.85))
        }
        .padding(.top, 2)
    }

    private var displayedAlbum: MusicAlbumItem? {
        if let browsedAlbumId,
           let album = model.musicAlbums.first(where: { $0.albumId == browsedAlbumId }) {
            return album
        }
        if let albumId = model.playback.track?.albumId, !albumId.isEmpty,
           let album = model.musicAlbums.first(where: { $0.albumId == albumId }) {
            return album
        }
        return model.musicAlbums.first
    }

    private var displayArtwork: UIImage? {
        displayedAlbum?.artwork ?? model.playback.track?.artwork
    }

    private var displayTitle: String {
        displayedAlbum?.title ?? model.playback.track?.title ?? "选一首开始播放"
    }

    private var displaySubtitle: String {
        if let album = displayedAlbum {
            return "\(album.artist) · \(album.trackCount) 首"
        }
        return subtitle
    }

    private var albumSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 42, abs(dx) > abs(value.translation.height) else { return }
                shiftAlbum(dx < 0 ? 1 : -1)
            }
    }

    private func shiftAlbum(_ step: Int) {
        guard !model.isMusicBusy else { return }
        if !model.musicAlbums.isEmpty {
            let albums = model.musicAlbums
            let currentIndex = albums.firstIndex(where: { $0.albumId == displayedAlbum?.albumId }) ?? 0
            let next = (currentIndex + step + albums.count) % albums.count
            withAnimation(.easeInOut(duration: 0.2)) {
                browsedAlbumId = albums[next].albumId
            }
            Task { await model.play(albums[next]) }
        } else if model.musicTracks.count > 1 {
            let tracks = model.musicTracks
            let currentIndex = tracks.firstIndex(where: { $0.trackId == model.playback.track?.trackId }) ?? 0
            let next = (currentIndex + step + tracks.count) % tracks.count
            browsedAlbumId = nil
            Task { await model.play(tracks[next]) }
        }
    }
    private var subtitle: String {
        guard let track = model.playback.track else {
            return "系统音乐资料库 · 本机文件 · 网易云"
        }
        if track.album.isEmpty || track.album == "本机文件" {
            return track.artist
        }
        return "\(track.artist) · \(track.album)"
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("资料库专辑")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("· \(model.musicAlbums.count) 张")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Button("刷新") {
                    Task { await model.loadMusicLibrary() }
                }
                .font(.system(size: 12, weight: .semibold))
                .tint(WhaleTheme.accent)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(model.musicAlbums) { album in
                        albumCard(album)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func albumCard(_ album: MusicAlbumItem) -> some View {
        Button {
            browsedAlbumId = album.albumId
            Task { await model.play(album) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                albumCover(album)
                    .frame(width: 196, height: 196)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: isCurrent(album) && model.playback.isPlaying ? "waveform" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                    }

                Text(album.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text("\(album.artist) · \(album.trackCount) 首")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: 196, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放专辑 \(album.title)")
    }

    @ViewBuilder
    private func albumCover(_ album: MusicAlbumItem) -> some View {
        if let image = album.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: albumColors(for: album.title),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(album.title.prefix(1)))
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    private var neteaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.openNetEaseMusic()
            } label: {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.98, green: 0.23, blue: 0.26), Color(red: 0.72, green: 0.05, blue: 0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay {
                            Text("云")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("网易云音乐")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WhaleTheme.ink)
                        Text("打开已登录的 App，继续播放你的歌单")
                            .font(.system(size: 12))
                            .foregroundStyle(WhaleTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WhaleTheme.accent)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)

            Text("iOS 不允许第三方 App 读取网易云的账号、歌单或受版权保护的音频。这里只负责打开 App，不会假装已经替你播放。")
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    libraryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(WhaleTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("曲库")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WhaleTheme.ink)
                        Text(librarySummary)
                            .font(.system(size: 11))
                            .foregroundStyle(WhaleTheme.muted)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.muted)
                        .rotationEffect(.degrees(libraryExpanded ? 180 : 0))
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if libraryExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.musicAlbums.isEmpty {
                        albumSection
                    }
                    libraryContent
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private var librarySummary: String {
        let trackPart = "\(model.musicTracks.count) 首"
        guard !model.musicAlbums.isEmpty else { return trackPart }
        return "\(trackPart) · \(model.musicAlbums.count) 张专辑"
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的曲库")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("· \(model.musicTracks.count) 首")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("导入", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(WhaleTheme.accent)
            }

            if let error = model.musicError, !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("导入音频") { showImporter = true }
                        Button("重新读取") { Task { await model.loadMusicLibrary() } }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(WhaleTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .whaleCard()
            }

            if model.musicTracks.isEmpty && model.musicAlbums.isEmpty {
                emptyLibrary
            } else if !model.musicTracks.isEmpty {
                trackList
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 13) {
            WhaleIconTile(systemName: "music.note", size: 68)
                .padding(.top, 8)
            Text("音乐库还没有歌曲")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("系统「音乐」资料库里有了专辑或歌曲后会自动出现在这里。也可以导入自己拥有的音频文件，或打开已登录的网易云音乐。")
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button {
                showImporter = true
            } label: {
                Label("导入音频文件", systemImage: "plus")
                    .whalePrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Button("了解音乐来源") { showSourceInfo = true }
                .font(.system(size: 13, weight: .medium))
                .tint(WhaleTheme.accent)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.musicTracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    browsedAlbumId = nil
                    Task { await model.play(track) }
                } label: {
                    HStack(spacing: 12) {
                        trackThumbnail(track)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(WhaleTheme.ink)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if track.isLocal {
                                    Text("本机")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(WhaleTheme.accentSoft, in: Capsule())
                                        .foregroundStyle(WhaleTheme.accent)
                                }
                                Text(trackMeta(track))
                                    .font(.system(size: 12))
                                    .foregroundStyle(WhaleTheme.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(track.durationText)
                            .font(.system(size: 11))
                            .foregroundStyle(WhaleTheme.muted)
                        Image(systemName: isCurrent(track) && model.playback.isPlaying ? "waveform" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WhaleTheme.accent)
                            .frame(width: 20)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if track.isLocal {
                        Button(role: .destructive) {
                            Task { await model.deleteLocalTrack(track) }
                        } label: {
                            Label("从鲸鱼删除", systemImage: "trash")
                        }
                    }
                }
                if index < model.musicTracks.count - 1 {
                    Divider().overlay(WhaleTheme.line).padding(.leading, 58)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func trackThumbnail(_ track: MusicTrackItem) -> some View {
        if let image = track.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [WhaleTheme.accent.opacity(0.55), WhaleTheme.accentDeep.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("系统音乐库未授权", systemImage: "lock.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("允许访问「媒体与 Apple Music」后，鲸鱼才能读取资料库里的歌曲和专辑。导入的本机文件不依赖这个权限。")
                .font(.system(size: 13))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if model.permissionsSnapshot["music"] == "denied" {
                Button("前往系统设置") { model.openSystemSettings() }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(WhaleTheme.accent)
            } else {
                Button("允许访问系统音乐库") {
                    Task { await model.requestMusicAccess() }
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(WhaleTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whaleCard()
    }

    private func trackMeta(_ track: MusicTrackItem) -> String {
        if track.album.isEmpty || track.album == "本机文件" {
            return track.artist
        }
        return "\(track.artist) · \(track.album)"
    }

    private func isCurrent(_ track: MusicTrackItem) -> Bool {
        model.playback.track?.trackId == track.trackId
    }

    private func isCurrent(_ album: MusicAlbumItem) -> Bool {
        model.playback.track?.albumId == album.albumId
    }

    private func albumColors(for title: String) -> [Color] {
        let palettes: [[Color]] = [
            [WhaleTheme.accent.opacity(0.85), WhaleTheme.accentDeep],
            [Color(red: 0.30, green: 0.55, blue: 0.92), Color(red: 0.16, green: 0.25, blue: 0.56)],
            [Color(red: 0.92, green: 0.48, blue: 0.52), Color(red: 0.55, green: 0.18, blue: 0.34)],
            [Color(red: 0.39, green: 0.72, blue: 0.58), Color(red: 0.10, green: 0.34, blue: 0.35)],
            [Color(red: 0.90, green: 0.66, blue: 0.28), Color(red: 0.55, green: 0.29, blue: 0.12)]
        ]
        let scalar = title.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % palettes.count }
        return palettes[scalar % palettes.count]
    }

    private var progressFraction: CGFloat {
        let duration = model.playback.track?.durationSec ?? 0
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(model.playback.positionSec / duration, 0), 1))
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "0:00" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct VinylDisc: View {
    let artwork: UIImage?
    let title: String
    let isPlaying: Bool
    let palette: [Color]

    @State private var angle: Double = 0
    @State private var ticker = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.15, green: 0.15, blue: 0.17), Color(red: 0.03, green: 0.03, blue: 0.04)],
                        center: .center,
                        startRadius: 8,
                        endRadius: 250
                    )
                )

            ForEach(0..<7, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                    .padding(CGFloat(16 + ring * 15))
            }

            Circle()
                .fill(Color.white.opacity(0.05))
                .padding(52)

            label
                .frame(width: 134, height: 134)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }

            Circle()
                .fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                .frame(width: 14, height: 14)

            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .rotationEffect(.degrees(angle))
        .shadow(color: Color.black.opacity(0.32), radius: 22, y: 12)
        .onReceive(ticker) { _ in
            guard isPlaying else { return }
            angle = (angle + 1.2).truncatingRemainder(dividingBy: 360)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(title.prefix(1)))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

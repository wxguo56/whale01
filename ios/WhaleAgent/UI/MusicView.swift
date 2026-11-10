import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var model: AppModel
    var showsClose = false

    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showSourceInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    searchField
                    playerCard
                    if !model.musicAlbums.isEmpty {
                        albumSection
                    }
                    neteaseCard
                    librarySection
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
        VStack(spacing: 15) {
            playerArtwork
                .frame(width: 214, height: 214)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: WhaleTheme.accent.opacity(0.2), radius: 18, y: 10)

            VStack(spacing: 5) {
                Text(model.playback.track?.title ?? "选一首开始播放")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 13))
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
                        .frame(width: 44, height: 44)
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
                    Task { await model.playNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .disabled(model.isMusicBusy)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var playerArtwork: some View {
        if let image = model.playback.track?.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [WhaleTheme.accent.opacity(0.88), WhaleTheme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: model.playback.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
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
                LazyHStack(alignment: .top, spacing: 13) {
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
            Task { await model.play(album) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                albumCover(album)
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: isCurrent(album) && model.playback.isPlaying ? "waveform" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                    }

                Text(album.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text("\(album.artist) · \(album.trackCount) 首")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
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
                    .font(.system(size: 48, weight: .bold, design: .rounded))
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

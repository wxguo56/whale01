import Combine
import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var model: AppModel
    var showsClose = false
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showSourceInfo = false
    @State private var libraryExpanded = false
    @State private var browsedAlbumId: String?
    @State private var dragOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var isSwitchingAlbum = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
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
        .background(ScrollOffsetMemory(key: embedded ? "music" : "music-sheet"))
        .background(WhaleTheme.pageGradient)
        .navigationTitle("音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .whaleFont(size: 15, weight: .semibold)
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

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .whaleFont(size: 14, weight: .semibold)
                .foregroundStyle(WhaleTheme.muted)
            TextField("搜索歌曲、艺人或专辑", text: $model.musicQuery)
                .whaleFont(size: 14)
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
                        .whaleFont(size: 15)
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
            albumDeck

            VStack(spacing: 5) {
                Text(displayTitle)
                    .whaleFont(size: 20, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(displaySubtitle)
                    .whaleFont(size: 13)
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
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 34) {
                Button {
                    Task { await model.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .whaleFont(size: 20, weight: .semibold)
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(width: 52, height: 44)
                }
                .disabled(model.isMusicBusy)

                Button {
                    Task { await model.togglePlayback() }
                } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .whaleFont(size: 24, weight: .bold)
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
                            .whaleFont(size: 17, weight: .semibold)
                        Text(model.musicPlayMode.title)
                            .whaleFont(size: 13, weight: .semibold)
                    }
                    .foregroundStyle(WhaleTheme.ink)
                    .frame(width: 62, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(model.musicPlayMode.title)
            }

            Text("左右滑动黑胶切换专辑")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted.opacity(0.85))
        }
        .padding(.top, 2)
    }

    private var albumDeck: some View {
        ZStack {
            VinylDisc(
                artwork: displayArtwork,
                title: displayTitle,
                isPlaying: model.playback.isPlaying,
                palette: albumColors(for: displayTitle)
            )
            .frame(width: 246, height: 246)
            .offset(x: dragOffset * 0.35)
            .scaleEffect(1 - min(abs(dragOffset), 180) / 180 * 0.05)
            .opacity(cardOpacity)
            .shadow(color: Color.black.opacity(0.45), radius: 26, y: 16)
            .contentShape(Circle())
            .gesture(albumSwipe)

            Tonearm(isPlaying: model.playback.isPlaying)
                .offset(x: 96, y: -34)
                .zIndex(2)
        }
        .frame(width: 300, height: 268)
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
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isSwitchingAlbum, !model.isMusicBusy else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !isSwitchingAlbum, !model.isMusicBusy else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
                    return
                }
                let dx = value.translation.width
                let projected = dx + value.predictedEndTranslation.width
                guard abs(dx) > abs(value.translation.height), abs(projected) > 60 else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
                    return
                }
                completeSwipe(dx < 0 ? 1 : -1)
            }
    }

    private func completeSwipe(_ step: Int) {
        guard !isSwitchingAlbum else { return }
        isSwitchingAlbum = true
        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset = -CGFloat(step) * 90
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            shiftAlbum(step)
            dragOffset = CGFloat(step) * 90
            withAnimation(.easeOut(duration: 0.26)) {
                dragOffset = 0
                cardOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isSwitchingAlbum = false
            }
        }
    }

    private func shiftAlbum(_ step: Int) {
        guard !model.isMusicBusy else { return }
        if !model.musicAlbums.isEmpty {
            let albums = model.musicAlbums
            let currentIndex = albums.firstIndex(where: { $0.albumId == displayedAlbum?.albumId }) ?? 0
            let next = (currentIndex + step + albums.count) % albums.count
            browsedAlbumId = albums[next].albumId
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
                    .whaleFont(size: 17, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                Text("· \(model.musicAlbums.count) 张")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Button("刷新") {
                    Task { await model.loadMusicLibrary() }
                }
                .whaleFont(size: 13, weight: .semibold)
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
                                    .whaleFont(size: 15, weight: .bold)
                                    .foregroundStyle(.white)
                            }
                            .padding(10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                    }

                Text(album.title)
                    .whaleFont(size: 15, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text("\(album.artist) · \(album.trackCount) 首")
                    .whaleFont(size: 13)
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
                    .whaleFont(size: 62, weight: .bold, design: .rounded)
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
                                .whaleFont(size: 22, weight: .bold, design: .rounded)
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("网易云音乐")
                            .whaleFont(size: 15, weight: .semibold)
                            .foregroundStyle(WhaleTheme.ink)
                        Text("打开已登录的 App，继续播放你的歌单")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app")
                        .whaleFont(size: 16, weight: .semibold)
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
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                libraryExpanded.toggle()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "music.note.list")
                        .whaleFont(size: 15, weight: .semibold)
                        .foregroundStyle(WhaleTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(WhaleTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("曲库")
                            .whaleFont(size: 15, weight: .semibold)
                            .foregroundStyle(WhaleTheme.ink)
                        Text(librarySummary)
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .whaleFont(size: 13, weight: .semibold)
                        .foregroundStyle(WhaleTheme.muted)
                        .rotationEffect(.degrees(libraryExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: libraryExpanded)
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
                    .whaleFont(size: 17, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                Text("· \(model.musicTracks.count) 首")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("导入", systemImage: "plus")
                        .whaleFont(size: 13, weight: .semibold)
                }
                .tint(WhaleTheme.accent)
            }

            if let error = model.musicError, !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "info.circle")
                        .whaleFont(size: 13)
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("导入音频") { showImporter = true }
                        Button("重新读取") { Task { await model.loadMusicLibrary() } }
                    }
                    .whaleFont(size: 13, weight: .semibold)
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
                .whaleFont(size: 19, weight: .semibold)
                .foregroundStyle(WhaleTheme.ink)
            Text("系统「音乐」资料库里有了专辑或歌曲后会自动出现在这里。也可以导入自己拥有的音频文件，或打开已登录的网易云音乐。")
                .whaleFont(size: 14)
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
                .whaleFont(size: 13, weight: .medium)
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
                                .whaleFont(size: 15, weight: .medium)
                                .foregroundStyle(WhaleTheme.ink)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if track.isLocal {
                                    Text("本机")
                                        .whaleFont(size: 13, weight: .semibold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(WhaleTheme.accentSoft, in: Capsule())
                                        .foregroundStyle(WhaleTheme.accent)
                                }
                                Text(trackMeta(track))
                                    .whaleFont(size: 13)
                                    .foregroundStyle(WhaleTheme.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(track.durationText)
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted)
                        Image(systemName: isCurrent(track) && model.playback.isPlaying ? "waveform" : "play.fill")
                            .whaleFont(size: 13, weight: .bold)
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
                    .whaleFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("系统音乐库未授权", systemImage: "lock.shield")
                .whaleFont(size: 15, weight: .semibold)
                .foregroundStyle(WhaleTheme.ink)
            Text("允许访问「媒体与 Apple Music」后，鲸鱼才能读取资料库里的歌曲和专辑。导入的本机文件不依赖这个权限。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if model.permissionsSnapshot["music"] == "denied" {
                Button("前往系统设置") { model.openSystemSettings() }
                    .whaleFont(size: 13, weight: .semibold)
                    .tint(WhaleTheme.accent)
            } else {
                Button("允许访问系统音乐库") {
                    Task { await model.requestMusicAccess() }
                }
                .whaleFont(size: 13, weight: .semibold)
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

private struct VinylBody: View {
    let artwork: UIImage?
    let title: String
    let palette: [Color]
    var angle: Double = 0

    var body: some View {
        ZStack {
            record
                .rotationEffect(.degrees(angle))
            specular
            rim
        }
    }

    private var record: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.13, green: 0.13, blue: 0.15),
                            Color(red: 0.06, green: 0.06, blue: 0.07),
                            Color(red: 0.02, green: 0.02, blue: 0.03)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 2,
                        endRadius: 150
                    )
                )

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                var ring = radius * 0.55
                var step = 0
                while ring < radius * 0.985 {
                    let alpha = step % 6 == 0 ? 0.055 : 0.02
                    let rect = CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)), lineWidth: 0.5)
                    ring += 1.6
                    step += 1
                }
            }

            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: 3)
                .padding(46)
                .blur(radius: 2)

            label
                .frame(width: 128, height: 128)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.06), Color.white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                }
                .shadow(color: Color.black.opacity(0.45), radius: 5, y: 2)

            spindle
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
                    .whaleFont(size: 44, weight: .heavy, design: .rounded)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        }
    }

    private var spindle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.62), Color(white: 0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 13, height: 13)
            .overlay {
                Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.6)
            }
            .overlay {
                Circle().fill(Color.black.opacity(0.6)).frame(width: 4.5, height: 4.5)
            }
            .shadow(color: Color.black.opacity(0.5), radius: 2, y: 1)
    }

    private var specular: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white.opacity(0.20), location: 0.075),
                            .init(color: .clear, location: 0.17),
                            .init(color: .clear, location: 0.50),
                            .init(color: .white.opacity(0.12), location: 0.575),
                            .init(color: .clear, location: 0.67)
                        ]),
                        center: .center
                    )
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 92
                    )
                )
                .frame(width: 190, height: 116)
                .rotationEffect(.degrees(-32))
                .offset(x: -44, y: -56)
                .blur(radius: 14)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private var rim: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.42), Color.white.opacity(0.04), Color.white.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.4
            )
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
        VinylBody(artwork: artwork, title: title, palette: palette, angle: angle)
            .onReceive(ticker) { _ in
                guard isPlaying else { return }
                angle = (angle + 1.0).truncatingRemainder(dividingBy: 360)
            }
    }
}

private struct Tonearm: View {
    let isPlaying: Bool

    private let frameHeight: CGFloat = 164
    private let pivotY: CGFloat = 26

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                counterweight
                    .frame(height: 26)
                tube
                    .frame(height: 112)
                headshell
                    .frame(height: 26)
            }
            .frame(width: 34, height: frameHeight, alignment: .top)
            .rotationEffect(
                .degrees(isPlaying ? 14 : -6),
                anchor: UnitPoint(x: 0.5, y: pivotY / frameHeight)
            )
            .animation(.spring(response: 0.62, dampingFraction: 0.72), value: isPlaying)

            base
                .offset(y: pivotY - 17)
        }
        .frame(width: 34, height: frameHeight, alignment: .top)
        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
    }

    private var counterweight: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.64), Color(white: 0.28), Color(white: 0.56)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 20)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1.6)
                    .padding(.vertical, 5)
                    .padding(.leading, 5)
            }
            .overlay {
                Capsule().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.6)
            }
    }

    private var tube: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.98), Color(white: 0.70), Color(white: 0.36), Color(white: 0.80)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 6.5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1.4)
                    .padding(.leading, 1.6)
            }
    }

    private var headshell: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.93), Color(white: 0.58), Color(white: 0.74)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 17, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.4), lineWidth: 0.7)
                }

            Capsule()
                .fill(Color(white: 0.20))
                .frame(width: 2.4, height: 9)
                .offset(y: 7)
        }
        .frame(width: 34, height: 26)
    }

    private var base: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.98), Color(white: 0.66), Color(white: 0.30), Color(white: 0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.5), radius: 5, y: 3)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .frame(width: 24, height: 24)

            Circle()
                .fill(Color(white: 0.16))
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.6)
                }
        }
    }
}

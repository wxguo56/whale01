import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var model: AppModel
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nowPlaying
                    searchArea
                    library
                    if model.permissionsSnapshot["music"] != "granted" {
                        permissionView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(WhaleTheme.background)
            .navigationTitle("音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("导入音乐文件")
                }
            }
            .task { await model.musicAppeared() }
            .refreshable {
                model.refreshPermissions()
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
        }
    }

    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                WhaleTheme.heroGradient
                Image(systemName: "music.note.list")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(.white.opacity(0.09))
                    .offset(x: 210, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    Label("系统音乐库", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("读取系统\n「音乐」App。")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("汽水音乐等第三方 App 下载的歌曲在各自沙盒里，iOS 不允许其他 App 读取。这类歌曲请用「导入音乐文件」，不需要授权。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
            .frame(minHeight: 235)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                Label("授权读取系统音乐库", systemImage: "lock.shield")
                    .font(.headline)
                Text("授权后可读取系统「音乐」App 里的曲目。导入的本机文件不依赖这个权限，鲸鱼也不会上传你的音乐。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.permissionsSnapshot["music"] == "denied" {
                    Button {
                        model.openSystemSettings()
                    } label: {
                        Text("前往系统设置")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WhaleTheme.accent)
                } else {
                    Button {
                        Task { await model.requestMusicAccess() }
                    } label: {
                        Text("允许访问音乐")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WhaleTheme.accent)
                    .disabled(model.isMusicBusy)
                }
            }
            .whaleCard()

            if let error = model.musicError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("正在播放", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(model.playback.stateText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 15) {
                artwork(url: model.playback.track?.artworkURL, size: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.playback.track?.title ?? "从音乐库选一首")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(model.playback.track?.artist ?? "音乐会在你确认后由系统播放")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    if let album = model.playback.track?.album, !album.isEmpty {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 24) {
                Spacer()
                Button {
                    Task { await model.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .disabled(model.isMusicBusy)

                Button {
                    Task { await model.togglePlayback() }
                } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WhaleTheme.ink)
                        .frame(width: 56, height: 56)
                        .background(.white, in: Circle())
                }
                .disabled(model.isMusicBusy)

                Button {
                    Task { await model.playNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .disabled(model.isMusicBusy)
                Spacer()
            }

            if model.playback.queueLength > 0 {
                Text("队列 \(model.playback.queueLength) 首 · \(model.playback.audioOutput ? "系统音频输出" : "等待播放")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [WhaleTheme.accentDeep, Color(red: 0.22, green: 0.10, blue: 0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: WhaleTheme.accentDeep.opacity(0.18), radius: 20, y: 10)
    }

    private var searchArea: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索歌名或艺人", text: $model.musicQuery)
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
                        .foregroundStyle(.tertiary)
                }
            }
            Button("搜索") {
                Task { await model.loadMusicLibrary() }
            }
            .font(.caption.weight(.semibold))
            .disabled(model.isMusicBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("你的音乐")
                    .font(.headline)
                Spacer()
                if model.isMusicBusy {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Text("\(model.musicTracks.count) 首")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showImporter = true
                } label: {
                    Label("导入", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(WhaleTheme.accent)
            }

            if let error = model.musicError, !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("导入音乐文件") { showImporter = true }
                        Button("重新读取") { Task { await model.loadMusicLibrary() } }
                    }
                    .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .whaleCard()
            } else if model.musicTracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.musicDidLoad ? "这里还没有歌" : "正在读取音乐库…")
                        .font(.subheadline.weight(.medium))
                    Text("用「导入音乐文件」选择手机或 iCloud 里的 mp3、m4a、wav，导入后就能直接播放。系统「音乐」App 里的曲目在授权后也会显示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入音乐文件", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WhaleTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 14)
                .whaleCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.musicTracks) { track in
                        Button {
                            Task { await model.play(track) }
                        } label: {
                            HStack(spacing: 12) {
                                artwork(url: track.artworkURL, size: 46)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        if track.isLocal {
                                            Text("本机")
                                                .font(.system(size: 9, weight: .semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(WhaleTheme.accent.opacity(0.12), in: Capsule())
                                                .foregroundStyle(WhaleTheme.accent)
                                        }
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(track.durationText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Image(systemName: model.playback.track?.id == track.id && model.playback.isPlaying ? "waveform" : "play.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhaleTheme.accent)
                                    .frame(width: 22)
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
                        if track.id != model.musicTracks.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func artwork(url: URL?, size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                artworkPlaceholder(size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            artworkPlaceholder(size: size)
        }
    }

    private func artworkPlaceholder(size: CGFloat) -> some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: size, height: size)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

import SwiftUI

struct MusicView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.permissionsSnapshot["music"] == "granted" {
                        nowPlaying
                        searchArea
                        library
                    } else {
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
                    WhaleStatusPill(
                        text: model.permissionsSnapshot["music"] == "granted" ? "音乐库" : "未授权",
                        color: model.permissionsSnapshot["music"] == "granted" ? .green : .orange
                    )
                }
            }
            .task { await model.musicAppeared() }
            .refreshable {
                model.refreshPermissions()
                await model.refreshPlayback()
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
                    Label("真实音乐库", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("播放你真正\n拥有的音乐。")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("鲸鱼通过 MusicKit 读取本机音乐库并控制播放，不会伪造曲目或音源。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
            .frame(minHeight: 235)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                Label("需要音乐库权限", systemImage: "lock.shield")
                    .font(.headline)
                Text("授权后，你可以搜索本机曲目、播放、暂停、继续和切换歌曲。鲸鱼不会上传你的音乐。")
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
                Text("你的音乐库")
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
            }

            if let error = model.musicError, !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重新读取音乐库") {
                        Task { await model.loadMusicLibrary() }
                    }
                    .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .whaleCard()
            } else if model.musicTracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.musicDidLoad ? "没有可显示的曲目" : "正在读取音乐库…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
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
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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

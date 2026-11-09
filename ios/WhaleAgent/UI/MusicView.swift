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
                VStack(spacing: 22) {
                    playerCard
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
            .background(WhaleTheme.background)
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
                Text("系统「音乐」App 里的歌曲需要音乐库授权。汽水音乐等第三方 App 的离线缓存位于各自的沙盒，iOS 不允许其他 App 读取，请先用「选取音频」导入你自己拥有的文件。")
            }
        }
    }

    private var playerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [WhaleTheme.accent.opacity(0.85), WhaleTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 240, height: 240)
                Image(systemName: model.playback.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(color: WhaleTheme.accent.opacity(0.2), radius: 18, y: 10)

            VStack(spacing: 5) {
                Text(model.playback.track?.title ?? "选一首开始播放")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(model.playback.track?.artist ?? "本机文件或系统音乐库")
                    .font(.system(size: 14))
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
        .padding(.top, 4)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的曲库")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text("· \(model.musicTracks.count) 首")
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("选取音频", systemImage: "plus")
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
                        Button("选取音频") { showImporter = true }
                        Button("重新读取") { Task { await model.loadMusicLibrary() } }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(WhaleTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .whaleCard()
            }

            if model.musicTracks.isEmpty {
                emptyLibrary
            } else {
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
            Text("系统「音乐」资料库里有了歌曲后，可以在这里选择播放。也可以选取自己拥有的音频文件。")
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button {
                showImporter = true
            } label: {
                Label("选取音频文件", systemImage: "plus")
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
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.line, lineWidth: 1)
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.musicTracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task { await model.play(track) }
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [WhaleTheme.accent.opacity(0.55), WhaleTheme.accentDeep.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
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
                                Text(track.artist)
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
        .background(WhaleTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.line, lineWidth: 1)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("系统音乐库未授权", systemImage: "lock.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("授权后可以读取系统「音乐」App 里的曲目。导入的本机文件不依赖这个权限。")
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

    private var progressFraction: CGFloat {
        let duration = model.playback.track?.durationSec ?? 0
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(model.playback.positionSec / duration, 0), 1))
    }

    private func isCurrent(_ track: MusicTrackItem) -> Bool {
        model.playback.track?.trackId == track.trackId
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "0:00" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

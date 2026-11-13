import SwiftUI

private struct ReadableFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: max(13, size), relativeTo: .body)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: design)) }
}

extension View {
    func whaleFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ReadableFont(size: size, weight: weight, design: design))
    }
    func whaleTouchTarget() -> some View { frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
}

struct InlinePlaybackView: View {
    @ObservedObject var model: AppModel
    let onOpen: () -> Void
    var body: some View {
        if let track = model.playback.track {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note").foregroundStyle(WhaleTheme.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.headline).foregroundStyle(WhaleTheme.ink).lineLimit(2)
                            Text(model.playback.isPlaying ? "正在播放" : "已暂停").font(.subheadline).foregroundStyle(WhaleTheme.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button { Task { await model.togglePlayback() } } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(WhaleTheme.accent).whaleTouchTarget()
                }.buttonStyle(.plain).disabled(model.isMusicBusy)
                    .accessibilityLabel(model.playback.isPlaying ? "暂停音乐" : "继续播放")
            }.whaleCard(padding: 14)
        }
    }
}

struct AssistantActivityView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.isBusy {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(model.activityDescription).font(.subheadline).foregroundStyle(WhaleTheme.muted)
                Spacer(minLength: 0)
                if model.canStopReply {
                    Button("停止") { model.stopReply() }.font(.subheadline).whaleTouchTarget()
                }
            }.padding(.vertical, 8)
        }
    }
}

struct DiscoverHubView: View {
    @ObservedObject var model: AppModel
    let onOpen: (DiscoverChannel) -> Void
    let onSettings: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("发现").font(.largeTitle.bold()).foregroundStyle(WhaleTheme.ink)
                    Spacer()
                    Button(action: onSettings) { Image(systemName: "gearshape").whaleTouchTarget() }
                        .accessibilityLabel("设置")
                }
                Text("想读的、想听的，都在这里。")
                    .font(.body).foregroundStyle(WhaleTheme.muted)
                InlinePlaybackView(model: model) { onOpen(.music) }
                VStack(spacing: 0) {
                    ForEach(DiscoverChannel.allCases) { channel in
                        Button { onOpen(channel) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: channel.icon).font(.title3).foregroundStyle(WhaleTheme.accent)
                                    .frame(width: 44, height: 44).background(WhaleTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(channel.title).font(.headline).foregroundStyle(WhaleTheme.ink)
                                    Text(channel.subtitle).font(.subheadline).foregroundStyle(WhaleTheme.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(WhaleTheme.muted)
                            }.padding(.vertical, 13).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(channel.title)
                        if channel != DiscoverChannel.allCases.last { Divider() }
                    }
                }.whaleCard()
            }.padding(20)
        }.scrollIndicators(.hidden).background(WhaleTheme.background)
            .background(ScrollOffsetMemory(key: "discover-hub"))
    }
}

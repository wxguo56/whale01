import SwiftUI

struct NewsDetailView: View {
    let item: NewsItem
    let channel: DiscoverChannel
    @Environment(\.dismiss) private var dismiss
    @State private var safari: SafariTarget?

    var body: some View {
        ZStack {
            WhaleBackdrop()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        meta
                        Text(item.displayTitle)
                            .whaleFont(size: 25, weight: .bold, design: .rounded)
                            .foregroundStyle(WhaleTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        summaryCard
                        sourceButton
                        copyrightNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .background(ScrollOffsetMemory(key: "article-" + item.id))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler().frame(width: 1, height: 1))
        .sheet(item: $safari) { target in
            InAppSafari(url: target.url)
                .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .whaleFont(size: 15, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle(size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Spacer()
            Text(channel.title)
                .whaleFont(size: 13, weight: .semibold)
                .foregroundStyle(WhaleTheme.muted)
            Spacer()
            if let url = item.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .whaleFont(size: 14, weight: .semibold)
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle(size: 44)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(WhaleTheme.heroGradient)
                .frame(height: 164)
            Circle()
                .fill(WhaleTheme.accent.opacity(0.32))
                .frame(width: 160, height: 160)
                .blur(radius: 28)
                .offset(x: 230, y: -60)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: channel == .ai ? "sparkles.rectangle.stack.fill" : channel == .game ? "gamecontroller.fill" : "newspaper.fill")
                    .whaleFont(size: 28, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.92))
                Text("来源摘要")
                    .whaleFont(size: 13, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
    }

    private var meta: some View {
        HStack(spacing: 7) {
            Text(item.source)
                .whaleFont(size: 13, weight: .semibold)
                .foregroundStyle(WhaleTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(WhaleTheme.accent.opacity(0.11), in: Capsule())
            Circle().fill(WhaleTheme.muted.opacity(0.5)).frame(width: 3, height: 3)
            Text(DiscoverFormat.relative(item.publishedAt))
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
            Spacer()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .whaleFont(size: 13, weight: .semibold)
                Text("鲸鱼摘要")
                    .whaleFont(size: 13, weight: .bold)
            }
            .foregroundStyle(WhaleTheme.accent)
            Text(item.displaySummary.isEmpty ? "这条资讯只提供标题，原文摘要需要打开来源查看。" : item.displaySummary)
                .whaleFont(size: 14)
                .foregroundStyle(WhaleTheme.ink.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("基于来源摘要整理，不替代原文。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WhaleTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8) }
    }

    private var sourceButton: some View {
        Button {
            if let url = item.url { safari = SafariTarget(url: url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                Text("阅读原文")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .whaleFont(size: 13, weight: .bold)
            }
            .whaleFont(size: 15, weight: .semibold)
            .foregroundStyle(WhaleTheme.onAccent)
            .padding(.horizontal, 17)
            .frame(height: 52)
            .background(WhaleTheme.auroraGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(item.url == nil)
    }

    private var copyrightNote: some View {
        Text("鲸鱼只提供标题、来源摘要与原文跳转，不转载全文。版权归原媒体所有。")
            .whaleFont(size: 13)
            .foregroundStyle(WhaleTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

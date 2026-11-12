import SwiftUI

struct GameDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: GameRankItem
    let board: GameRankBoard
    @StateObject private var model: GameDetailModel
    @State private var showFullDescription = false

    init(item: GameRankItem, board: GameRankBoard) {
        self.item = item
        self.board = board
        _model = StateObject(wrappedValue: GameDetailModel(item: item))
    }

    var body: some View {
        ZStack {
            WhaleBackdrop()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        heroCard
                        rankCard
                        if let detail = model.detail {
                            metricsCard(detail)
                            reachCard(detail)
                            descriptionCard(detail)
                            screenshotCard(detail)
                        } else {
                            detailState
                        }
                        Text("来源：Apple App Store 中国区公开接口（RSS 榜单 / lookup）。榜单与详情随 App Store 实时变化。")
                            .font(.system(size: 9))
                            .foregroundStyle(WhaleTheme.muted.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.load() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler().frame(width: 1, height: 1))
        .task { await model.load() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle(size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text("\(board.title) · 第 \(item.rank) 名")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
            if let url = (model.detail?.appStoreURL ?? item.url) {
                Link(destination: url) {
                    Text("App Store")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhaleTheme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: model.detail?.iconURL ?? item.iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(WhaleTheme.soft)
                            .overlay {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 26, weight: .light))
                                    .foregroundStyle(WhaleTheme.muted)
                            }
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.detail?.trackName ?? item.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(2)
                    Text(model.detail?.artistName ?? item.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        chip(model.detail?.primaryGenreName ?? item.category)
                        if let price = model.detail?.formattedPrice {
                            chip(price)
                        }
                        chip(board.title)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhaleTheme.warm)
                Text(model.detail?.ratingText ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WhaleTheme.ink)
                Text(model.detail?.ratingCountText ?? "评分数加载中")
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text("上架 \(model.detail?.releaseText ?? item.releaseText)")
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前榜单")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                    Text(board.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                }
                Spacer()
                Text("#\(item.rank)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WhaleTheme.accent)
            }
            Text("排名来自 App Store 中国区游戏分类榜单，按 Apple 公开排序展示。")
                .font(.system(size: 9))
                .foregroundStyle(WhaleTheme.muted.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func metricsCard(_ detail: AppStoreAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("应用资料")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                stat("类别", detail.primaryGenreName ?? item.category)
                stat("价格", detail.formattedPrice ?? "—")
                stat("大小", detail.sizeText)
                stat("版本", detail.version ?? "—")
                stat("评分", detail.ratingText)
                stat("评分数", detail.ratingCountText)
                stat("上架时间", detail.releaseText)
                stat("最近更新", detail.updateText)
                stat("最低系统", detail.minimumOsVersion ?? "—")
                stat("年龄分级", detail.contentAdvisoryRating ?? "—")
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func reachCard(_ detail: AppStoreAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("下载量与收入")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WhaleTheme.ink)

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.warm)
                    .padding(.top, 1)
                Text("Apple 不公开单款游戏的下载量与收入金额，这里只展示真实可核对的数据，不做编造。")
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            reachRow("下载量", value: "未公开", note: "用评分数与榜单排名代表真实热度")
            reachRow("评分数", value: detail.ratingCountText, note: "越高说明评价用户越多")
            reachRow(
                "收入",
                value: board == .grossing ? "畅销榜第 \(item.rank) 名" : "免费榜不提供收入排名",
                note: board == .grossing ? "畅销榜反映收入强弱，具体金额需第三方估算" : "可查看畅销榜了解收入排名"
            )
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func descriptionCard(_ detail: AppStoreAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("游戏介绍")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Spacer()
                if !detail.descriptionText.isEmpty {
                    Button(showFullDescription ? "收起" : "展开") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showFullDescription.toggle()
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                    .buttonStyle(.plain)
                }
            }
            if detail.descriptionText.isEmpty {
                Text("App Store 没有提供这个应用的介绍。")
                    .font(.system(size: 11))
                    .foregroundStyle(WhaleTheme.muted)
            } else {
                Text(detail.descriptionText)
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.ink.opacity(0.86))
                    .lineSpacing(3)
                    .lineLimit(showFullDescription ? nil : 6)
            }
        }
        .padding(15)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func screenshotCard(_ detail: AppStoreAppDetail) -> some View {
        if !detail.screenshots.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("截图")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(Array(detail.screenshots.enumerated()), id: \.offset) { entry in
                            AsyncImage(url: URL(string: entry.element)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(WhaleTheme.soft)
                                }
                            }
                            .frame(width: 132, height: 236)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
            .padding(15)
            .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    private var detailState: some View {
        switch model.state {
        case .loading, .idle:
            VStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(WhaleTheme.soft)
                        .frame(height: 92)
                        .redacted(reason: .placeholder)
                }
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重新加载") {
                    Task { await model.load() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhaleTheme.onAccent)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(WhaleTheme.auroraGradient, in: Capsule())
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        case .loaded:
            EmptyView()
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(WhaleTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WhaleTheme.field.opacity(0.72), in: Capsule())
            .lineLimit(1)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(WhaleTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(WhaleTheme.field.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func reachRow(_ label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(note)
                .font(.system(size: 9))
                .foregroundStyle(WhaleTheme.muted.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WhaleTheme.field.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

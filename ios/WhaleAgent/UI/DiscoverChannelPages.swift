import SwiftUI

struct DiscoverChannelPage: View {
    @ObservedObject var model: DiscoverModel
    @ObservedObject var appModel: AppModel

    var body: some View {
        switch model.channel {
        case .ai:
            AIChannelPage(model: model)
        case .market:
            MarketChannelPage(model: model)
        case .game:
            GameChannelPage(model: model)
        case .music:
            MusicChannelPage(model: model, appModel: appModel)
        case .headline:
            HeadlineChannelPage(model: model)
        case .weibo:
            WeiboChannelPage(model: model)
        }
    }
}

// MARK: - AI

struct AIChannelPage: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DiscoverChannelHeader(channel: .ai)
                newsHero
                AIPaperSection(model: model)
                moreNews
                NewsSourceFooter(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .task { await model.loadInitial() }
    }

    @ViewBuilder
    private var newsHero: some View {
        if model.newsState == .loading && model.newsItems.isEmpty {
            NewsSkeleton()
        } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
            DiscoverErrorState(message: message) {
                Task { await model.loadNews(channel: .ai, force: true) }
            }
        } else if let feature = model.newsItems.first {
            NavigationLink(value: DiscoverRoute.news(feature)) {
                NewsFeatureCard(item: feature)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var moreNews: some View {
        if model.newsItems.count > 1 {
            DiscoverSectionTitle(title: "更多 AI 资讯", subtitle: "公开 RSS · 阅读全文请跳转原文")
            ForEach(Array(model.newsItems.dropFirst())) { item in
                NavigationLink(value: DiscoverRoute.news(item)) {
                    NewsRowCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AIPaperSection: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionTitle(
                title: "arXiv 最新论文",
                subtitle: model.papersSource.isEmpty
                    ? "按提交时间排序 · 点击阅读原文"
                    : "\(model.papersSource) · 按提交时间排序"
            )

            AIPaperCategoryBar(selection: model.paperCategory) { category in
                Task { await model.selectPaperCategory(category) }
            }

            if model.papers.isEmpty {
                switch model.papersState {
                case .failed(let message):
                    DiscoverErrorState(message: message) {
                        Task { await model.loadPapers(category: model.paperCategory, force: true) }
                    }
                case .idle, .loading:
                    VStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(WhaleTheme.soft)
                                .frame(height: 118)
                                .redacted(reason: .placeholder)
                        }
                    }
                case .loaded:
                    Text("这个分类暂时没有新的论文")
                        .font(.system(size: 12))
                        .foregroundStyle(WhaleTheme.muted)
                        .padding(.vertical, 14)
                }
            } else {
                ForEach(model.papers) { paper in
                    AIPaperCard(paper: paper)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - A 股

struct MarketChannelPage: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                DiscoverChannelHeader(channel: .market)
                MarketSearchField(text: $model.searchQuery) {
                    model.clearSearch()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if isSearching {
                        searchResults
                    } else {
                        marketOverview
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.loadMarket(force: true) }
        }
        .task { await model.loadInitial() }
        .onChange(of: model.searchQuery) { _, _ in
            model.scheduleSearch()
        }
    }

    private var isSearching: Bool {
        !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var searchResults: some View {
        switch model.searchState {
        case .loading, .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(WhaleTheme.accent)
                Text("正在搜索 A 股与指数")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
        case .failed(let message):
            DiscoverErrorState(message: message) {
                model.scheduleSearch()
            }
        case .loaded:
            ForEach(model.searchResults) { result in
                NavigationLink(value: DiscoverRoute.search(result)) {
                    HStack(spacing: 12) {
                        WhaleIconTile(systemName: result.type == "index" ? "chart.bar.xaxis" : "building.columns", size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WhaleTheme.ink)
                            Text(result.displayCode)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(WhaleTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WhaleTheme.muted.opacity(0.5))
                    }
                    .padding(14)
                    .background(WhaleTheme.card.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var marketOverview: some View {
        if model.marketState == .loading && model.indexes.isEmpty && model.watchQuotes.isEmpty {
            NewsSkeleton()
        } else if case .failed(let message) = model.marketState, model.indexes.isEmpty && model.watchQuotes.isEmpty {
            DiscoverErrorState(message: message) {
                Task { await model.loadMarket(force: true) }
            }
        } else {
            if !model.indexes.isEmpty {
                DiscoverSectionTitle(title: "指数", subtitle: "红涨绿跌 · 公开延迟行情")
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(model.indexes) { quote in
                            NavigationLink(value: DiscoverRoute.stock(quote)) {
                                MarketIndexCard(quote: quote)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }

            if model.watchQuotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自选还是空的")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                    Text("在上方搜索股票或指数，进入详情后加入自选。不会预置任何示例价格。")
                        .font(.system(size: 12))
                        .foregroundStyle(WhaleTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(WhaleTheme.card.opacity(0.62), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
                }
            } else {
                DiscoverSectionTitle(title: "我的自选", subtitle: "\(model.watchQuotes.count) 只 · 长按可从自选移除")
                ForEach(model.watchQuotes) { quote in
                    NavigationLink(value: DiscoverRoute.stock(quote)) {
                        QuoteRowCard(quote: quote, flow: model.watchFlows[quote.symbol])
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            model.removeFromWatchlist(quote.symbol)
                        } label: {
                            Label("从自选移除", systemImage: "star.slash")
                        }
                    }
                }

                if !model.watchFlows.isEmpty {
                    DiscoverSectionTitle(title: "资金动向 · 自选", subtitle: "今日主力资金 · 东方财富公开数据")
                    ForEach(model.watchQuotes) { quote in
                        if let flow = model.watchFlows[quote.symbol] {
                            WatchFundFlowCard(quote: quote, flow: flow)
                        }
                    }
                }
            }

            MarketDisclaimer(source: model.marketSource, updatedAt: model.marketUpdatedAt)
        }
    }
}

struct WatchFundFlowCard: View {
    let quote: StockQuote
    let flow: FundFlowPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(quote.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                Text(quote.displayCode)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text("主力 \(DiscoverFormat.signedCompactAmount(flow.mainNet))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(flow.isInflow ? WhaleTheme.danger : WhaleTheme.success)
            }
            HStack(spacing: 6) {
                flowCell("超大单", flow.superLargeNet)
                flowCell("大单", flow.largeNet)
                flowCell("中单", flow.mediumNet)
                flowCell("小单", flow.smallNet)
            }
        }
        .padding(13)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        }
    }

    private func flowCell(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(WhaleTheme.muted)
            Text(DiscoverFormat.signedCompactAmount(value))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle((value ?? 0) >= 0 ? WhaleTheme.danger : WhaleTheme.success)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 游戏

struct GameChannelPage: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                DiscoverChannelHeader(channel: .game)
                GameSectionSegment(selection: $model.gameSection) { section in
                    Task { await model.selectGameSection(section) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if model.gameSection == .news {
                newsContent
            } else {
                rankContent
            }
        }
        .task { await model.loadInitial() }
    }

    private var newsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                newsBody
                NewsSourceFooter(model: model, extra: "游戏频道来自游戏媒体公开 RSS，不是微信公众号。")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var newsBody: some View {
        if model.newsState == .loading && model.newsItems.isEmpty {
            NewsSkeleton()
        } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
            DiscoverErrorState(message: message) {
                Task { await model.loadNews(channel: .game, force: true) }
            }
        } else {
            if let feature = model.newsItems.first {
                NavigationLink(value: DiscoverRoute.news(feature)) {
                    NewsFeatureCard(item: feature)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(model.newsItems.dropFirst())) { item in
                NavigationLink(value: DiscoverRoute.news(item)) {
                    NewsRowCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rankContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                switch model.rankState {
                case .loading where model.rankItems.isEmpty, .idle:
                    NewsSkeleton()
                case .failed(let message) where model.rankItems.isEmpty:
                    DiscoverErrorState(message: message) {
                        if let board = model.gameSection.board {
                            Task { await model.loadRank(board, force: true) }
                        }
                    }
                default:
                    GameRankHeader(
                        title: model.gameSection.title,
                        source: model.rankSource,
                        updatedAt: model.rankUpdatedAt,
                        count: model.rankItems.count
                    )
                    ForEach(model.rankItems) { item in
                        if let url = item.url {
                            Link(destination: url) {
                                GameRankRowCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            GameRankRowCard(item: item)
                        }
                    }
                    Text("来源：\(model.rankSource)；榜单随 App Store 实时变化，排名不代表推荐。")
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            if let board = model.gameSection.board {
                await model.loadRank(board, force: true)
            }
        }
    }
}

// MARK: - 音乐

struct MusicChannelPage: View {
    @ObservedObject var model: DiscoverModel
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            DiscoverChannelHeader(channel: .music)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)
            MusicView(model: appModel, embedded: true)
        }
    }
}

// MARK: - 时事

struct HeadlineChannelPage: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                DiscoverChannelHeader(channel: .headline)
                if model.newsState == .loading && model.newsItems.isEmpty {
                    NewsSkeleton()
                } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
                    DiscoverErrorState(message: message) {
                        Task { await model.loadNews(channel: .headline, force: true) }
                    }
                } else {
                    if let feature = model.newsItems.first {
                        NavigationLink(value: DiscoverRoute.news(feature)) {
                            NewsFeatureCard(item: feature)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(model.newsItems.dropFirst())) { item in
                        NavigationLink(value: DiscoverRoute.news(item)) {
                            NewsRowCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                NewsSourceFooter(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .task { await model.loadInitial() }
    }
}

// MARK: - 微博

struct WeiboChannelPage: View {
    @ObservedObject var model: DiscoverModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                DiscoverChannelHeader(channel: .weibo)
                switch model.hotState {
                case .loading where model.hotItems.isEmpty, .idle:
                    NewsSkeleton()
                case .failed(let message) where model.hotItems.isEmpty:
                    DiscoverErrorState(message: message) {
                        Task { await model.loadWeiboHot(force: true) }
                    }
                default:
                    WeiboHotHeader(
                        source: model.hotSource,
                        updatedAt: model.hotUpdatedAt,
                        count: model.hotItems.count
                    )
                    ForEach(model.hotItems) { item in
                        if let url = item.url {
                            Link(destination: url) {
                                WeiboHotRowCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            WeiboHotRowCard(item: item)
                        }
                    }
                    Text("来源：\(model.hotSource)；\(model.hotNote)")
                        .font(.system(size: 9))
                        .foregroundStyle(WhaleTheme.muted.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.loadWeiboHot(force: true) }
        .task { await model.loadInitial() }
    }
}

// MARK: - Shared

struct NewsSourceFooter: View {
    @ObservedObject var model: DiscoverModel
    var extra: String? = nil

    var body: some View {
        VStack(spacing: 5) {
            Text("只展示标题与来源摘要，阅读全文请跳转原文。")
            if let extra {
                Text(extra)
            }
            if !model.newsSources.isEmpty {
                Text("来源：\(model.newsSources.joined(separator: " · "))")
                    .lineLimit(2)
            }
            if let updatedAt = model.newsUpdatedAt {
                Text("更新于 \(DiscoverFormat.relative(updatedAt))")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(WhaleTheme.muted.opacity(0.82))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

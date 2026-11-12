import SwiftUI

struct DiscoverView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DiscoverModel
    @State private var path = NavigationPath()

    init(initialChannel: DiscoverChannel) {
        _model = StateObject(wrappedValue: DiscoverModel(initialChannel: initialChannel))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WhaleBackdrop()
                VStack(spacing: 0) {
                    topChrome
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DiscoverRoute.self) { route in
                switch route {
                case .news(let item):
                    NewsDetailView(item: item, channel: model.channel)
                case .stock(let quote):
                    StockDetailView(quote: quote, discover: model)
                case .search(let result):
                    StockSeedLoaderView(result: result, discover: model)
                }
            }
        }
        .task { await model.loadInitial() }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
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
                    Text("发现")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                    Text("真实资讯 · 微博热搜 · 游戏榜单 · 行情")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small).tint(WhaleTheme.accent)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WhaleTheme.ink)
                            .whaleGlassCircle(size: 34)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新")
            }

            DiscoverSegment(selection: $model.channel) { channel in
                Task { await model.select(channel) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.channel {
        case .ai, .headline:
            newsContent
        case .game:
            gameContent
        case .weibo:
            weiboContent
        case .market:
            marketContent
        }
    }

    private var gameContent: some View {
        VStack(spacing: 0) {
            GameSectionSegment(selection: $model.gameSection) { section in
                Task { await model.selectGameSection(section) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            if model.gameSection == .news {
                newsContent
            } else {
                gameRankContent
            }
        }
    }

    private var gameRankContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch model.rankState {
                case .loading where model.rankItems.isEmpty, .idle:
                    NewsSkeleton().padding(.top, 6)
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
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            if let board = model.gameSection.board {
                await model.loadRank(board, force: true)
            }
        }
    }

    private var newsContent: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                switch model.newsState {
                case .loading where model.newsItems.isEmpty, .idle:
                    NewsSkeleton().padding(.top, 6)
                case .failed(let message) where model.newsItems.isEmpty:
                    DiscoverErrorState(message: message) {
                        Task { await model.loadNews(channel: model.channel, force: true) }
                    }
                default:
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
                    newsFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    private var weiboContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch model.hotState {
                case .loading where model.hotItems.isEmpty, .idle:
                    NewsSkeleton().padding(.top, 6)
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
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.loadWeiboHot(force: true) }
    }

    private var newsFooter: some View {
        VStack(spacing: 5) {
            Text("只展示标题与来源摘要，阅读全文请跳转原文。")
            if model.channel == .game {
                Text("游戏频道来自游戏媒体公开 RSS，不是微信公众号。")
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

    private var marketContent: some View {
        VStack(spacing: 0) {
            MarketSearchField(text: $model.searchQuery) {
                model.clearSearch()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .onChange(of: model.searchQuery) { _, _ in
                model.scheduleSearch()
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResults
                    } else {
                        marketOverview
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.loadMarket(force: true) }
        }
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
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
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
                    .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
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
                .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
            } else {
                DiscoverSectionTitle(title: "我的自选", subtitle: "\(model.watchQuotes.count) 只 · 长按详情可移除")
                ForEach(model.watchQuotes) { quote in
                    NavigationLink(value: DiscoverRoute.stock(quote)) {
                        QuoteRowCard(quote: quote)
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
            }

            MarketDisclaimer(source: model.marketSource, updatedAt: model.marketUpdatedAt)
        }
    }

    private var isRefreshing: Bool {
        if model.channel == .market { return model.marketState == .loading }
        if model.channel == .game, model.gameSection.board != nil { return model.rankState == .loading }
        if model.channel == .weibo { return model.hotState == .loading }
        return model.newsState == .loading
    }
}

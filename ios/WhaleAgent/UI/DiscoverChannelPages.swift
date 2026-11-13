import SwiftUI

struct DiscoverChannelPage: View {
    @ObservedObject var model: DiscoverModel
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let notice = model.dataNotice {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(WhaleTheme.soft)
                    .accessibilityLabel(notice)
            }
        }
    }

    @ViewBuilder private var content: some View {
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
        VStack(spacing: 0) {
            NewsSectionBar(channel: .ai, selection: model.aiSection) { section in
                Task { await model.selectNewsSection(section, for: .ai) }
            }.padding(.horizontal, 16).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 1).id("ai-top")
                        VStack(alignment: .leading, spacing: 12) {
                            newsHero
                            moreNews
                        }
                        .horizontalTabSwipe(
                            onPrevious: { model.stepNewsSection(.ai, by: -1) },
                            onNext: { model.stepNewsSection(.ai, by: 1) }
                        )
                        NewsSourceFooter(model: model)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)

                .background(ScrollOffsetMemory(key: "ai-\(model.aiSection)"))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-reading-ai")
                .refreshable { await model.refresh() }
                .onChange(of: model.aiSection) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("ai-top", anchor: .top) }
                }
                .task { await model.loadInitial() }
            }
        }
    }

    @ViewBuilder
    private var newsHero: some View {
        if model.newsState == .loading && model.newsItems.isEmpty {
            NewsSkeleton()
        } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
            DiscoverErrorState(message: message) {
                Task { await model.loadNews(channel: .ai, force: true) }
            }
        } else if let feature = model.aiNews.first {
            NavigationLink(value: DiscoverRoute.news(feature)) {
                NewsFeatureCard(item: feature)
            }
            .buttonStyle(.plain)
        } else if model.newsState == .loaded {
            Text("这个分类暂时没有新的资讯，换一个分类或下拉刷新。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var moreNews: some View {
        if model.aiNews.count > 1 {
            DiscoverSectionTitle(title: "更多动态", subtitle: "公开 RSS · 阅读全文请跳转原文")
            ForEach(Array(model.aiNews.dropFirst())) { item in
                NavigationLink(value: DiscoverRoute.news(item)) {
                    NewsRowCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
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
            .background(ScrollOffsetMemory(key: "market"))
            .scrollDismissesKeyboard(.interactively)
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
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
        case .failed(let message):
            DiscoverErrorState(message: message) {
                model.scheduleSearch()
            }
        case .loaded, .cached, .stale, .partial:
            ForEach(model.searchResults) { result in
                NavigationLink(value: DiscoverRoute.search(result)) {
                    HStack(spacing: 12) {
                        WhaleIconTile(systemName: result.type == "index" ? "chart.bar.xaxis" : "building.columns", size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .whaleFont(size: 15, weight: .semibold)
                                .foregroundStyle(WhaleTheme.ink)
                            Text(result.displayCode)
                                .whaleFont(size: 13, design: .monospaced)
                                .foregroundStyle(WhaleTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .whaleFont(size: 13, weight: .semibold)
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
                        .whaleFont(size: 15, weight: .semibold)
                        .foregroundStyle(WhaleTheme.ink)
                    Text("在上方搜索股票或指数，进入详情后加入自选。不会预置任何示例价格。")
                        .whaleFont(size: 13)
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
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                Text(quote.displayCode)
                    .whaleFont(size: 13, design: .monospaced)
                    .foregroundStyle(WhaleTheme.muted)
                Spacer()
                Text("主力 \(DiscoverFormat.signedCompactAmount(flow.mainNet))")
                    .whaleFont(size: 13, weight: .bold, design: .rounded)
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
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
            Text(DiscoverFormat.signedCompactAmount(value))
                .whaleFont(size: 13, weight: .semibold, design: .rounded)
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
    @State private var safari: SafariTarget?

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

            Group {
                if model.gameSection == .news {
                    newsContent
                } else if let kind = model.gameSection.steamKind {
                    steamContent(kind)
                } else {
                    rankContent
                }
            }
            .id(model.gameSection.rawValue)
            .horizontalTabSwipe(
                onPrevious: swipePrevious,
                onNext: swipeNext
            )
        }
        .task { await model.loadInitial() }
        .sheet(item: $safari) { target in
            InAppSafari(url: target.url)
                .ignoresSafeArea()
        }
    }

    private func swipePrevious() {
        if model.gameSection == .news,
           let index = DiscoverChannel.game.newsSections.firstIndex(where: { $0.id == model.gameNewsSection }),
           index > 0 {
            model.stepNewsSection(.game, by: -1)
        } else {
            Task { await model.stepGameSection(by: -1) }
        }
    }

    private func swipeNext() {
        let sections = DiscoverChannel.game.newsSections
        if model.gameSection == .news,
           let index = sections.firstIndex(where: { $0.id == model.gameNewsSection }),
           index < sections.count - 1 {
            model.stepNewsSection(.game, by: 1)
        } else {
            Task { await model.stepGameSection(by: 1) }
        }
    }

    private var newsContent: some View {
        VStack(spacing: 0) {
            NewsSectionBar(channel: .game, selection: model.gameNewsSection) { section in
                Task { await model.selectNewsSection(section, for: .game) }
            }.padding(.horizontal, 16).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        Color.clear.frame(height: 1).id("game-news-top")
                        newsBody
                        NewsSourceFooter(model: model, extra: "游戏频道来自游戏媒体公开 RSS，不是微信公众号。")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)

                .background(ScrollOffsetMemory(key: "game-news"))
                .refreshable { await model.refresh() }
                .onChange(of: model.gameNewsSection) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("game-news-top", anchor: .top) }
                }
            }
        }
    }

    @ViewBuilder
    private var newsBody: some View {
        if model.newsState == .loading && model.newsItems.isEmpty {
            NewsSkeleton()
        } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
            DiscoverErrorState(message: message) {
                Task { await model.loadNews(channel: .game, force: true) }
            }
        } else if model.gameNews.isEmpty {
            Text("这个分类暂时没有新的游戏资讯，换一个分类或下拉刷新。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        } else {
            if let feature = model.gameNews.first {
                NavigationLink(value: DiscoverRoute.news(feature)) {
                    NewsFeatureCard(item: feature)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(model.gameNews.dropFirst())) { item in
                NavigationLink(value: DiscoverRoute.news(item)) {
                    NewsRowCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func steamContent(_ kind: SteamKind) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                switch model.steamState {
                case .loading where model.steam == nil, .idle:
                    NewsSkeleton()
                case .failed(let message) where model.steam == nil:
                    DiscoverErrorState(message: message) {
                        Task { await model.loadSteam(kind: kind, force: true) }
                    }
                default:
                    SteamHeader(kind: kind, count: model.steamItems(kind: kind).count)
                    ForEach(Array(model.steamItems(kind: kind).enumerated()), id: \.element.id) { index, item in
                        if let url = item.storeURL {
                            Button { safari = SafariTarget(url: url) } label: {
                                SteamRowCard(item: item, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                        } else {
                            SteamRowCard(item: item, rank: index + 1)
                        }
                    }
                    if model.steamItems(kind: kind).isEmpty {
                        Text("Steam 本次没有返回该栏目条目，请稍后刷新。")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    }
                    if let updated = model.steam?.updatedAt {
                        Text("来源：Steam 商店中国区公开接口 · 更新于 \(DiscoverFormat.relative(updated)) · 点击条目打开 Steam 商店")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(ScrollOffsetMemory(key: "game-steam-\(kind.rawValue)"))
        .refreshable { await model.loadSteam(kind: kind, force: true) }
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
                        if let board = model.gameSection.board {
                            NavigationLink(value: DiscoverRoute.game(item, board)) {
                                GameRankRowCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            GameRankRowCard(item: item)
                        }
                    }
                    Text("点击任意游戏查看更多资料与榜单表现。来源：\(model.rankSource)；排名随 App Store 实时变化，不代表推荐。")
                        .whaleFont(size: 13)
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
        .background(ScrollOffsetMemory(key: "game-rank-\(model.gameSection.rawValue)"))
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
        VStack(spacing: 0) {
            NewsSectionBar(channel: .headline, selection: model.headlineSection) { section in
                Task { await model.selectNewsSection(section, for: .headline) }
            }.padding(.horizontal, 16).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        Color.clear.frame(height: 1).id("headline-top")
                        VStack(alignment: .leading, spacing: 11) {
                            if model.newsState == .loading && model.newsItems.isEmpty {
                                NewsSkeleton()
                            } else if case .failed(let message) = model.newsState, model.newsItems.isEmpty {
                                DiscoverErrorState(message: message) {
                                    Task { await model.loadNews(channel: .headline, force: true) }
                                }
                            } else if model.headlineNews.isEmpty {
                                Text("这个分类暂时没有新的资讯，换一个分类或下拉刷新。")
                                    .whaleFont(size: 13)
                                    .foregroundStyle(WhaleTheme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                            } else {
                                if let feature = model.headlineNews.first {
                                    NavigationLink(value: DiscoverRoute.news(feature)) {
                                        NewsFeatureCard(item: feature)
                                    }
                                    .buttonStyle(.plain)
                                }
                                ForEach(Array(model.headlineNews.dropFirst())) { item in
                                    NavigationLink(value: DiscoverRoute.news(item)) {
                                        NewsRowCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .horizontalTabSwipe(
                            onPrevious: { model.stepNewsSection(.headline, by: -1) },
                            onNext: { model.stepNewsSection(.headline, by: 1) }
                        )
                        NewsSourceFooter(model: model)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)

                .background(ScrollOffsetMemory(key: "headline-\(model.headlineSection)"))
                .refreshable { await model.refresh() }
                .onChange(of: model.headlineSection) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("headline-top", anchor: .top) }
                }
                .task { await model.loadInitial() }
            }
        }
    }
}

// MARK: - 微博

struct WeiboChannelPage: View {
    @ObservedObject var model: DiscoverModel
    @State private var safari: SafariTarget?

    var body: some View {
        VStack(spacing: 0) {
            HotBoardBar(selection: model.hotBoard) { board in
                Task { await model.selectHotBoard(board) }
            }.padding(.horizontal, 16).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    DiscoverChannelHeader(channel: .weibo)
                    switch model.hotState {
                    case .loading where model.hotItems.isEmpty, .idle:
                        NewsSkeleton()
                    case .failed(let message) where model.hotItems.isEmpty:
                        DiscoverErrorState(message: message) {
                            Task { await model.loadHot(force: true) }
                        }
                    default:
                        WeiboHotHeader(
                            board: model.hotBoard,
                            source: model.hotSource,
                            updatedAt: model.hotUpdatedAt,
                            count: model.hotItems.count
                        )
                        ForEach(model.hotItems) { item in
                            if let url = item.url {
                                Button { safari = SafariTarget(url: url) } label: {
                                    WeiboHotRowCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                WeiboHotRowCard(item: item)
                            }
                        }
                        Text("来源：\(model.hotSource)；\(model.hotNote)")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .horizontalTabSwipe(
                    onPrevious: { model.stepHotBoard(by: -1) },
                    onNext: { model.stepHotBoard(by: 1) }
                )
            }
            .scrollIndicators(.hidden)

            .background(ScrollOffsetMemory(key: "weibo"))
            .refreshable { await model.loadHot(force: true) }
            .task { await model.loadInitial() }
            .sheet(item: $safari) { target in
                InAppSafari(url: target.url)
                    .ignoresSafeArea()
            }
        }
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
        .whaleFont(size: 13)
        .foregroundStyle(WhaleTheme.muted.opacity(0.82))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

struct NewsSectionBar: View {
    let channel: DiscoverChannel
    let selection: String
    let onSelect: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(channel.newsSections) { option in
                        Button { onSelect(option.id) } label: {
                            Text(option.title).whaleFont(size: 13, weight: .semibold)
                                .whaleRaisedPill(selected: selection == option.id)
                        }.buttonStyle(.plain).id(option.id)
                            .accessibilityAddTraits(selection == option.id ? .isSelected : [])
                            .accessibilityIdentifier("discover-section-" + channel.rawValue + "-" + option.id)
                    }
                }.padding(.vertical, 8)
            }.scrollIndicators(.hidden).scrollClipDisabled()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-sections-" + channel.rawValue)
                .onChange(of: selection) { _, next in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(next, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

struct HotBoardBar: View {
    let selection: HotBoard
    let onSelect: (HotBoard) -> Void
    var body: some View {
        HStack(spacing: 7) {
            ForEach(HotBoard.allCases) { board in
                Button { onSelect(board) } label: {
                    Label(board.title, systemImage: board.icon).whaleFont(size: 13, weight: .semibold)
                        .whaleRaisedPill(selected: selection == board)
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == board ? .isSelected : [])
                    .accessibilityIdentifier("discover-hot-" + board.rawValue)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }
}

struct SteamHeader: View {
    let kind: SteamKind
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WhaleTheme.auroraGradient)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: kind == .specials ? "tag.fill" : kind == .comingSoon ? "calendar.badge.clock" : "flame.fill")
                        .whaleFont(size: 18, weight: .semibold)
                        .foregroundStyle(WhaleTheme.onAccent.opacity(0.92))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .whaleFont(size: 16, weight: .bold, design: .rounded)
                    .foregroundStyle(WhaleTheme.ink)
                Text(kind.subtitle)
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("\(count) 款")
                .whaleFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(WhaleTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(WhaleTheme.accent.opacity(0.1), in: Capsule())
        }
        .padding(13)
        .background(WhaleTheme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
        .whaleSoftElevation()
    }
}

struct SteamRowCard: View {
    let item: SteamItem
    let rank: Int

    var body: some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .whaleFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundStyle(rank <= 3 ? WhaleTheme.onAccent : WhaleTheme.muted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(rank <= 3 ? WhaleTheme.accent : WhaleTheme.soft.opacity(0.7)))

            AsyncImage(url: item.headerURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(WhaleTheme.soft)
                        .overlay {
                            Image(systemName: "gamecontroller.fill")
                                .whaleFont(size: 14)
                                .foregroundStyle(WhaleTheme.muted.opacity(0.6))
                        }
                }
            }
            .frame(width: 84, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.6) }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let discount = item.discountText {
                        Text(discount)
                            .whaleFont(size: 13, weight: .bold, design: .rounded)
                            .foregroundStyle(WhaleTheme.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WhaleTheme.success, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    if let original = item.originalPriceText {
                        Text(original)
                            .whaleFont(size: 13, design: .rounded)
                            .foregroundStyle(WhaleTheme.muted)
                            .strikethrough(true, color: WhaleTheme.muted)
                    }
                    Text(item.finalPriceText)
                        .whaleFont(size: 13, weight: .bold, design: .rounded)
                        .foregroundStyle(item.discountText == nil ? WhaleTheme.ink : WhaleTheme.success)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .whaleFont(size: 13, weight: .bold)
                .foregroundStyle(WhaleTheme.muted.opacity(0.55))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(WhaleTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7) }
        .whaleSoftElevation()
    }
}

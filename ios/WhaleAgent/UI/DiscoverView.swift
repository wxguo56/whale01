import SwiftUI

struct DiscoverView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appModel: AppModel
    @State private var path = NavigationPath()
    @State private var channel: DiscoverChannel
    @StateObject private var store: DiscoverChannelStore

    init(initialChannel: DiscoverChannel, appModel: AppModel) {
        _channel = State(initialValue: initialChannel)
        _store = StateObject(wrappedValue: DiscoverChannelStore())
        self.appModel = appModel
    }

    private var models: [DiscoverChannel: DiscoverModel] { store.models }
    private var activeModel: DiscoverModel? { store.models[channel] }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WhaleBackdrop()
                VStack(spacing: 0) {
                    topChrome
                    pager
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
#if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if environment["WHALE_DEMO_GAME"] == "1", let gameModel = models[.game] {
                    channel = .game
                    gameModel.gameSection = .grossing
                    await gameModel.selectGameSection(.grossing)
                    if let first = gameModel.rankItems.first {
                        path.append(DiscoverRoute.game(first, .grossing))
                    }
                }
                if let raw = environment["WHALE_DEMO_GAME_SECTION"],
                   let section = GameSection(rawValue: raw),
                   let gameModel = models[.game] {
                    channel = .game
                    gameModel.gameSection = section
                    await gameModel.selectGameSection(section)
                }
#endif
            }
            .navigationDestination(for: DiscoverRoute.self) { route in
                if let model = models[channel] {
                    switch route {
                    case .news(let item):
                        NewsDetailView(item: item, channel: channel)
                    case .stock(let quote):
                        StockDetailView(quote: quote, discover: model)
                    case .search(let result):
                        StockSeedLoaderView(result: result, discover: model)
                    case .game(let item, let board):
                        GameDetailView(item: item, board: board)
                    }
                }
            }
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(DiscoverChannel.allCases) { item in
                    if let model = models[item] {
                        DiscoverChannelPage(model: model, appModel: appModel)
                            .containerRelativeFrame(.horizontal)
                            .id(item)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(0, for: .scrollContent)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: channelScroll)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
    }

    private var channelScroll: Binding<DiscoverChannel?> {
        Binding(
            get: { channel },
            set: { next in
                guard let next, next != channel else { return }
                channel = next
            }
        )
    }

    private func select(_ next: DiscoverChannel) {
        guard next != channel else { return }
        withAnimation(.snappy(duration: 0.28)) { channel = next }
    }

    private var isRefreshing: Bool {
        guard let model = activeModel else { return false }
        switch channel {
        case .market:
            return model.marketState == .loading
        case .game:
            return model.gameSection.board == nil ? model.newsState == .loading : model.rankState == .loading
        case .weibo:
            return model.hotState == .loading
        case .ai:
            return model.newsState == .loading || model.papersState == .loading
        case .music:
            return false
        case .headline:
            return model.newsState == .loading
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle(size: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                VStack(alignment: .leading, spacing: 2) {
                    Text("发现")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(WhaleTheme.ink)
                    Text("左右滑动切换频道 · 真实数据")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WhaleTheme.muted)
                }
                Spacer()

                if channel != .music {
                    Button {
                        Task { await activeModel?.refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small).tint(WhaleTheme.accent)
                                .frame(width: 38, height: 38)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(WhaleTheme.ink)
                                .whaleGlassCircle(size: 38)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新")
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(WhaleChromeBackground())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhaleTheme.line.opacity(0.55)).frame(height: 0.6)
        }
    }
}

@MainActor
final class DiscoverChannelStore: ObservableObject {
    let models: [DiscoverChannel: DiscoverModel]

    init() {
        var built: [DiscoverChannel: DiscoverModel] = [:]
        for item in DiscoverChannel.allCases {
            built[item] = DiscoverModel(initialChannel: item)
        }
        models = built
    }
}

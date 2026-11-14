import SwiftUI

struct DiscoverView: View {
    @Binding var selection: DiscoverChannel
    @ObservedObject var appModel: AppModel
    let onSettings: () -> Void
    @State private var path = NavigationPath()
    @StateObject private var store: DiscoverChannelStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<DiscoverChannel>, appModel: AppModel, onSettings: @escaping () -> Void) {
        _selection = selection
        self.onSettings = onSettings
        _store = StateObject(wrappedValue: DiscoverChannelStore.shared)
        self.appModel = appModel
    }

    private var models: [DiscoverChannel: DiscoverModel] { store.models }
    var body: some View {
        ZStack {
            WhaleBackdrop()
            VStack(spacing: 0) {
                header
                DiscoverChannelBar(selection: $selection)
                NavigationStack(path: $path) {
                    ZStack {
                        WhaleBackdrop()
                        if let model = models[selection] {
                            DiscoverChannelPage(model: model, appModel: appModel)
                                .id(selection)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("discover-content-" + selection.rawValue)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
                    .background(Color.clear)
                    .toolbar(.hidden, for: .navigationBar)
                    .task {
#if DEBUG
                        let environment = ProcessInfo.processInfo.environment
                        if environment["WHALE_DEMO_GAME"] == "1", let gameModel = models[.game] {
                            gameModel.gameSection = .grossing
                            await gameModel.selectGameSection(.grossing)
                            if let first = gameModel.rankItems.first {
                                path.append(DiscoverRoute.game(first, .grossing))
                            }
                        }
                        if let raw = environment["WHALE_DEMO_GAME_SECTION"],
                           let section = GameSection(rawValue: raw),
                           let gameModel = models[.game] {
                            gameModel.gameSection = section
                            await gameModel.selectGameSection(section)
                        }
                        if let raw = environment["WHALE_DEMO_AI_SECTION"],
                           let aiModel = models[.ai] {
                            await aiModel.selectNewsSection(raw, for: .ai)
                        }
                        if let raw = environment["WHALE_DEMO_HEADLINE_SECTION"],
                           let headlineModel = models[.headline] {
                            await headlineModel.selectNewsSection(raw, for: .headline)
                        }
                        if let raw = environment["WHALE_DEMO_HOT_BOARD"],
                           let board = HotBoard(rawValue: raw),
                           let hotModel = models[.weibo] {
                            hotModel.hotBoard = board
                            await hotModel.loadHot(force: true)
                        }
                        if environment["WHALE_DEMO_STOCK"] == "1", models[.market] != nil {
                            let seed = StockSearchResult(
                                symbol: "sh600519",
                                code: "600519",
                                name: "贵州茅台",
                                market: "SH",
                                type: "stock"
                            )
                            path.append(DiscoverRoute.search(seed))
                        }
#endif
                    }
                    .navigationDestination(for: DiscoverRoute.self) { route in
                        if let model = models[selection] {
                            switch route {
                            case .news(let item):
                                NewsDetailView(item: item, channel: selection)
                            case .stock(let quote):
                                StockDetailView(quote: quote, discover: model)
                            case .search(let result):
                                StockSeedLoaderView(result: result, discover: model)
                            case .game(let item, let board):
                                GameDetailView(item: item, board: board)
                            }
                        }
                    }
                    .onChange(of: selection) { _, _ in path = NavigationPath() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("发现").font(.title2.bold()).foregroundStyle(WhaleTheme.ink)
            Text(selection.title).font(.subheadline).foregroundStyle(WhaleTheme.muted)
                .accessibilityIdentifier("discover-current-channel")
            Spacer(minLength: 0)
            Button(action: onSettings) { Image(systemName: "gearshape").whaleTouchTarget() }
                .foregroundStyle(WhaleTheme.accent).accessibilityLabel("设置")
                .accessibilityIdentifier("discover-settings")
        }.frame(minHeight: 52).padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("discover-fixed-header")
    }

}

struct DiscoverChannelBar: View {
    @Binding var selection: DiscoverChannel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(DiscoverChannel.allCases) { channel in
                        Button { selection = channel } label: {
                            Text(channel.tabTitle).whaleFont(size: 14, weight: .semibold)
                                .whaleChannelLabel(channel, selected: selection == channel)
                        }.buttonStyle(.plain).id(channel)
                            .accessibilityLabel(channel.title)
                            .accessibilityAddTraits(selection == channel ? .isSelected : [])
                            .accessibilityIdentifier("discover-channel-" + channel.rawValue)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.scrollIndicators(.hidden).scrollClipDisabled()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-channel-selector")
                .onChange(of: selection) { _, channel in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(channel, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

@MainActor
final class DiscoverChannelStore: ObservableObject {
    static let shared = DiscoverChannelStore()
    let models: [DiscoverChannel: DiscoverModel]

    private init() {
        var built: [DiscoverChannel: DiscoverModel] = [:]
        for item in DiscoverChannel.allCases {
            built[item] = DiscoverModel(initialChannel: item)
        }
        models = built
    }
}

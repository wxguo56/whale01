import SwiftUI

struct DiscoverView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appModel: AppModel
    @State private var path = NavigationPath()
    private let channel: DiscoverChannel
    private let returnTitle: String
    @StateObject private var store: DiscoverChannelStore

    init(initialChannel: DiscoverChannel, appModel: AppModel, returnTitle: String = "发现") {
        channel = initialChannel
        self.returnTitle = returnTitle
        _store = StateObject(wrappedValue: DiscoverChannelStore.shared)
        self.appModel = appModel
    }

    private var models: [DiscoverChannel: DiscoverModel] { store.models }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WhaleBackdrop()
                if let model = models[channel] {
                    DiscoverChannelPage(model: model, appModel: appModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .overlay(alignment: .leading) {
                if path.isEmpty { edgeBackZone }
            }
            .navigationTitle(channel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if path.isEmpty {
                        Button { dismiss() } label: { Label(returnTitle, systemImage: "chevron.left") }
                            .accessibilityLabel("返回" + returnTitle)
                    }
                }
            }
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

    private var edgeBackZone: some View {
        Color.clear
            .frame(width: 24)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard value.translation.width > 60,
                              abs(value.translation.height) < 90 else { return }
                        if path.isEmpty { dismiss() } else { path.removeLast() }
                    }
            )
            .accessibilityHidden(true)
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

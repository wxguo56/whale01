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
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WhaleBackdrop()
                pager
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .leading) {
                edgeBackZone
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
                        dismiss()
                    }
            )
            .accessibilityHidden(true)
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

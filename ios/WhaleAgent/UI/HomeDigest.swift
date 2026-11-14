import Combine
import SwiftUI

/// Home entry ticker.
///
/// Every line comes from data the app has already fetched (or its on-disk
/// cache). When a source has nothing yet the card falls back to the static
/// subtitle instead of inventing content.
@MainActor
final class HomeDigestModel: ObservableObject {
    @Published private(set) var lines: [DiscoverChannel: [String]] = [:]

    private let models: [DiscoverChannel: DiscoverModel]
    private var cancellables = Set<AnyCancellable>()
    private var lastPrime: Date = .distantPast

    init(models: [DiscoverChannel: DiscoverModel]? = nil) {
        let resolved = models ?? DiscoverChannelStore.shared.models
        self.models = resolved
        Publishers.MergeMany(resolved.map { $0.value.objectWillChange })
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        rebuild()
    }

    /// Warm the shared caches in the background so the ticker is real.
    /// Throttled: home is opened many times per minute.
    func prime(minInterval: TimeInterval = 120) async {
        guard Date().timeIntervalSince(lastPrime) >= minInterval else { return }
        lastPrime = Date()
        for (channel, model) in models {
            switch channel {
            case .ai, .headline, .game:
                Task { await model.loadNews(channel: channel, force: false) }
            case .market:
                Task { await model.loadMarket(force: false) }
            case .weibo:
                Task { await model.loadHot(force: false) }
            case .music:
                break
            }
        }
    }

    private func rebuild() {
        var next: [DiscoverChannel: [String]] = [:]
        if let items = models[.ai]?.newsItems, !items.isEmpty {
            next[.ai] = Self.newsLines(items)
        }
        if let market = models[.market] {
            let rows = Self.marketLines(indexes: market.indexes, watch: market.watchQuotes)
            if !rows.isEmpty { next[.market] = rows }
        }
        if let items = models[.game]?.newsItems, !items.isEmpty {
            next[.game] = Self.newsLines(items)
        }
        if let items = models[.headline]?.newsItems, !items.isEmpty {
            next[.headline] = Self.newsLines(items)
        }
        if let items = models[.weibo]?.hotItems, !items.isEmpty {
            next[.weibo] = Self.hotLines(items)
        }
        lines = next
    }

    static func newsLines(_ items: [NewsItem], limit: Int = 4) -> [String] {
        items.prefix(limit).compactMap { item in
            let title = item.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }

    static func marketLines(indexes: [StockQuote], watch: [StockQuote], limit: Int = 4) -> [String] {
        (indexes + watch).compactMap { quote -> String? in
            guard let price = quote.price else { return nil }
            return "\(shortName(quote.name)) \(String(format: "%.2f", price)) \(DiscoverFormat.percent(quote.changePercent))"
        }.prefix(limit).map { $0 }
    }

    static func hotLines(_ items: [WeiboHotItem], limit: Int = 4) -> [String] {
        items.prefix(limit).map { item in
            let word = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.hotText.isEmpty ? word : "\(word) · \(item.hotText)"
        }
    }

    private static func shortName(_ name: String) -> String {
        if name.contains("上证") { return "上证" }
        if name.contains("深证") || name.contains("深成") { return "深证" }
        if name.contains("创业板") { return "创业板" }
        if name.contains("科创") { return "科创50" }
        return name.replacingOccurrences(of: "指数", with: "")
    }
}

/// One-line ticker: the newest summary slides in from below while the previous
/// one leaves upward. Reduce Motion shows a single static line.
struct RollingSummaryText: View {
    let lines: [String]
    var delay: Double = 0
    var interval: Double = 5.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private var current: String {
        guard !lines.isEmpty else { return "" }
        return lines[min(index, lines.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(current)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(index)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 15)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.first ?? "")
        .accessibilityHint(lines.count > 1 ? "共 \(lines.count) 条摘要，自动轮播" : "")
        .task(id: lines) {
            index = 0
            guard lines.count > 1, !reduceMotion else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                index = (index + 1) % max(lines.count, 1)
            }
        }
    }
}

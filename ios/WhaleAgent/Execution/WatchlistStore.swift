import Combine
import Foundation

/// 本机自选列表。发现页与系统工具共用同一份存储，避免“助手说已加入、界面却没有”的分裂状态。
@MainActor
final class WatchlistStore: ObservableObject {
    static let shared = WatchlistStore()
    static let storageKey = "whale.market.watchlist"

    @Published private(set) var symbols: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        symbols = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func contains(_ symbol: String) -> Bool {
        symbols.contains(symbol.lowercased())
    }

    @discardableResult
    func add(_ symbol: String) -> Bool {
        let normalized = symbol.lowercased()
        guard !normalized.isEmpty, !symbols.contains(normalized) else { return false }
        symbols.append(normalized)
        persist()
        return true
    }

    @discardableResult
    func remove(_ symbol: String) -> Bool {
        let normalized = symbol.lowercased()
        let before = symbols.count
        symbols.removeAll { $0 == normalized }
        guard symbols.count != before else { return false }
        persist()
        return true
    }

    private func persist() {
        defaults.set(symbols, forKey: Self.storageKey)
    }
}

import Foundation

actor OperationLedger {
    static let shared = OperationLedger()

    private let storageKey = "whale.operation.ledger.v1"
    private let capacity = 100
    private var outcomes: [String: CachedToolOutcome] = [:]
    private var order: [String] = []

    init() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: CachedToolOutcome].self, from: data)
        else {
            return
        }
        outcomes = decoded
        order = Array(decoded.keys)
    }

    func outcome(for operationId: String) -> CachedToolOutcome? {
        outcomes[operationId]
    }

    func record(operationId: String, outcome: CachedToolOutcome) {
        outcomes[operationId] = outcome
        order.removeAll { $0 == operationId }
        order.append(operationId)
        while order.count > capacity {
            let oldest = order.removeFirst()
            outcomes.removeValue(forKey: oldest)
        }
        if let data = try? JSONEncoder().encode(outcomes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

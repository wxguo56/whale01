import Foundation

struct PendingWrite: Codable, Sendable {
    let operationId: String
    let tool: String
    let title: String
    let dueAt: String?
    let startAt: String?
    let createdAt: Date
}

actor OperationLedger {
    static let shared = OperationLedger()

    private let storageKey = "whale.operation.ledger.v1"
    private let pendingKey = "whale.operation.pending.v1"
    private let capacity = 100
    private var outcomes: [String: CachedToolOutcome] = [:]
    private var order: [String] = []
    private var pendingWrites: [String: PendingWrite] = [:]

    init() {
        if let pendingData = UserDefaults.standard.data(forKey: pendingKey),
           let pending = try? JSONDecoder().decode([String: PendingWrite].self, from: pendingData) {
            pendingWrites = pending
        }
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

    func markPending(_ write: PendingWrite) {
        pendingWrites[write.operationId] = write
        persistPending()
    }

    func listPendingWrites() -> [PendingWrite] {
        pendingWrites.values.sorted { $0.createdAt < $1.createdAt }
    }

    func resolvePending(operationId: String, outcome: CachedToolOutcome) {
        pendingWrites.removeValue(forKey: operationId)
        persistPending()
        record(operationId: operationId, outcome: outcome)
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pendingWrites) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }
}

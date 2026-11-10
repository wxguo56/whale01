import Foundation

struct PendingWrite: Codable, Sendable {
    let operationId: String
    let tool: String
    let title: String
    let dueAt: String?
    let startAt: String?
    let createdAt: Date
    var action: String? = nil
    var recordId: String? = nil
}

actor OperationLedger {
    static let shared = OperationLedger()

    private let storageKey = "whale.operation.ledger.v1"
    private let pendingKey = "whale.operation.pending.v1"
    private let recordsKey = "whale.operation.records.v1"
    private let capacity = 100
    private let recordCapacity = 200
    private var outcomes: [String: CachedToolOutcome] = [:]
    private var order: [String] = []
    private var pendingWrites: [String: PendingWrite] = [:]
    private var records: [OperationRecord] = []

    init() {
        if let pendingData = UserDefaults.standard.data(forKey: pendingKey),
           let pending = try? JSONDecoder().decode([String: PendingWrite].self, from: pendingData) {
            pendingWrites = pending
        }
        if let recordData = UserDefaults.standard.data(forKey: recordsKey),
           let decodedRecords = try? JSONDecoder().decode([OperationRecord].self, from: recordData) {
            records = decodedRecords
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

    func recordAction(_ record: OperationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        records.sort { $0.createdAt > $1.createdAt }
        if records.count > recordCapacity {
            records.removeLast(records.count - recordCapacity)
        }
        persistRecords()
    }

    func listActions(limit: Int = 120) -> [OperationRecord] {
        Array(records.prefix(max(0, limit)))
    }

    func clearActions() {
        records = []
        persistRecords()
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pendingWrites) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }
}

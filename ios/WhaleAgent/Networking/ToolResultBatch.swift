import Foundation

/// Partial deliveries survive history trimming and process restarts. Only
/// results for the current batch can be collected; repeated IDs are receipts.
struct ToolResultBatch: Codable, Sendable {
    let expected: [String]
    private(set) var results: [ToolResultPayload] = []
    var receivedIDs: Set<String> { Set(results.map(\.toolCallId)) }
    var isComplete: Bool { Set(expected).isSubset(of: receivedIDs) }
    var orderedResults: [ToolResultPayload] {
        expected.compactMap { id in results.first { $0.toolCallId == id } }
    }
    mutating func collect(_ input: [ToolResultPayload]) -> [ToolResultPayload] {
        let allowed = Set(expected)
        var seen = receivedIDs
        let novel = input.filter { allowed.contains($0.toolCallId) && seen.insert($0.toolCallId).inserted }
        results.append(contentsOf: novel)
        return novel
    }
}

actor TurnReceiptStore {
    private let defaults: UserDefaults
    private let key = "whale.local.completed.receipts.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func response(for turnId: String) -> AgentTurnResponse? {
        load().first { $0.turnId == turnId }
    }
    func record(_ response: AgentTurnResponse) {
        var responses = load().filter { $0.turnId != response.turnId }
        responses.append(response)
        if let data = try? JSONEncoder().encode(Array(responses.suffix(40))) { defaults.set(data, forKey: key) }
    }
    private func load() -> [AgentTurnResponse] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AgentTurnResponse].self, from: data)) ?? []
    }
}

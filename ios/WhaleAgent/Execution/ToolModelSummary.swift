import Foundation

/// Model context is a bounded projection of local evidence. The complete
/// payload stays in the local ledger for UI and recovery.
enum ToolModelSummary {
    private static let localOnly: Set<String> = [
        "latitude", "longitude", "coordinate", "coordinates", "gps", "phone",
        "phoneNumber", "recipientPhone", "email", "emailAddress", "contactNumbers"
    ]

    static func project(_ value: JSONValue, depth: Int = 0) -> JSONValue {
        guard depth < 10 else { return .string("内容层级已截断") }
        switch value {
        case .object(let object):
            return .object(object.filter { !localOnly.contains($0.key) }.mapValues { project($0, depth: depth + 1) })
        case .array(let array):
            return .array(array.prefix(20).map { project($0, depth: depth + 1) })
        case .string(let string): return .string(String(string.prefix(4000)))
        default: return value
        }
    }

    static func result(_ result: ToolResultPayload) -> ToolResultPayload {
        var budget = 12000
        return ToolResultPayload(toolCallId: result.toolCallId, status: result.status,
                          data: result.data.map { bounded($0, budget: &budget) }, error: result.error,
                          deduplicated: result.deduplicated)
    }

    private static func bounded(_ value: JSONValue, budget: inout Int, depth: Int = 0) -> JSONValue {
        guard budget > 0, depth < 10 else { return .string("模型摘要已截断；完整结果保留在本机") }
        switch value {
        case .object(let object):
            var result: [String: JSONValue] = [:]
            let provenance = ["source", "sources", "fetchedAt", "updatedAt", "locatedAt", "openedAt", "simulated", "priceDataAvailable", "evidenceCount"]
            let ordered = provenance.filter { object[$0] != nil } + object.keys.filter { !provenance.contains($0) }.sorted()
            for key in ordered where !localOnly.contains(key) {
                budget -= key.count
                if budget <= 0 { result["truncatedForModel"] = .bool(true); break }
                result[key] = bounded(object[key]!, budget: &budget, depth: depth + 1)
            }
            return .object(result)
        case .array(let array):
            var result: [JSONValue] = []
            for item in array.prefix(20) where budget > 0 { result.append(bounded(item, budget: &budget, depth: depth + 1)) }
            return .array(result)
        case .string(let string):
            let clipped = String(string.prefix(max(0, min(4000, budget))))
            budget -= clipped.count
            return .string(clipped)
        default: budget -= 16; return value
        }
    }
}

struct LocalTaskState: Codable, Sendable {
    var goal: String
    var observations: [String: String] = [:]
    var remaining: [String] = []
    var constraints: [String: String]? = nil

    var hasUnresolvedResults: Bool {
        observations.values.contains { $0 != "success" }
    }

    func payload(status: String) -> JSONValue {
        .object([
            "goal": .string(goal), "status": .string(status),
            "observations": .object(observations.mapValues(JSONValue.string)),
            "remaining": .array(remaining.map(JSONValue.string)),
            "constraints": .object((constraints ?? [:]).mapValues(JSONValue.string)),
            "requiresReview": .bool(hasUnresolvedResults)
        ])
    }
}

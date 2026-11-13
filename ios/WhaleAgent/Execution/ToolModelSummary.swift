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
        ToolResultPayload(toolCallId: result.toolCallId, status: result.status,
                          data: result.data.map { project($0) }, error: result.error,
                          deduplicated: result.deduplicated)
    }
}

struct LocalTaskState: Codable, Sendable {
    var goal: String
    var observations: [String: String] = [:]
    var remaining: [String] = []

    var hasUnresolvedResults: Bool {
        observations.values.contains { $0 != "success" }
    }

    func payload(status: String) -> JSONValue {
        .object([
            "goal": .string(goal), "status": .string(status),
            "observations": .object(observations.mapValues(JSONValue.string)),
            "remaining": .array(remaining.map(JSONValue.string)),
            "requiresReview": .bool(hasUnresolvedResults)
        ])
    }
}

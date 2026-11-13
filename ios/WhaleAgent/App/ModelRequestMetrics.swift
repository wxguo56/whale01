import Foundation

enum ModelRequestMetrics {
    struct Usage: Decodable, Sendable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
    }
    private struct Sample: Codable {
        let requestId: String
        let seconds: Double
        let promptTokens: Int
        let completionTokens: Int
        let succeeded: Bool
    }
    private static let lock = NSLock()
    private static let key = "whale.model.requests.v1"
    static var lastSuccessAt: Date? { UserDefaults.standard.object(forKey: "whale.model.lastSuccessAt") as? Date }

    static func record(requestId: String, seconds: Double, usage: Usage?, succeeded: Bool) {
        lock.lock(); defer { lock.unlock() }
        let existing = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Sample].self, from: $0) } ?? []
        let sample = Sample(requestId: requestId, seconds: seconds,
                            promptTokens: usage?.prompt_tokens ?? 0, completionTokens: usage?.completion_tokens ?? 0,
                            succeeded: succeeded)
        if let data = try? JSONEncoder().encode(Array((existing + [sample]).suffix(60))) { UserDefaults.standard.set(data, forKey: key) }
        if succeeded { UserDefaults.standard.set(Date(), forKey: "whale.model.lastSuccessAt") }
    }
    static var summary: String {
        guard let data = UserDefaults.standard.data(forKey: key), let samples = try? JSONDecoder().decode([Sample].self, from: data), !samples.isEmpty else { return "暂无真实模型请求记录" }
        let prompt = samples.reduce(0) { $0 + $1.promptTokens }
        let completion = samples.reduce(0) { $0 + $1.completionTokens }
        return "最近 \(samples.count) 次 · 输入 \(prompt) / 输出 \(completion) tokens · 失败 \(samples.filter { !$0.succeeded }.count) 次"
    }
}

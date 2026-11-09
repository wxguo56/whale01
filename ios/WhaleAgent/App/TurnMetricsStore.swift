import Foundation

/// Lightweight, on-device latency samples for the first model response of a turn.
/// Samples are kept in UserDefaults; no payload or user text is stored.
enum TurnMetricsStore {
    private static let key = "whale.turn.metrics.v1"
    private static let capacity = 40

    static func record(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        var values = load()
        values.append(seconds)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
        UserDefaults.standard.set(values, forKey: key)
    }

    static func samples() -> [Double] {
        load()
    }

    static func percentile(_ p: Double) -> Double? {
        let values = load().sorted()
        guard !values.isEmpty else { return nil }
        let position = Double(values.count - 1) * p
        let index = max(0, min(values.count - 1, Int(position.rounded())))
        return values[index]
    }

    static var summary: String {
        let values = load()
        guard !values.isEmpty, let p50 = percentile(0.5), let p95 = percentile(0.95) else {
            return "暂无样本（至少完成一轮对话后显示）"
        }
        return String(format: "p50 %.1fs · p95 %.1fs · 样本 %d", p50, p95, values.count)
    }

    private static func load() -> [Double] {
        (UserDefaults.standard.array(forKey: key) as? [Double]) ?? []
    }
}

/// Native tool timings, kept separately from model latency so the two are never conflated.
enum ToolMetricsStore {
    private struct Sample: Codable {
        let tool: String
        let seconds: Double
    }

    private static let key = "whale.tool.metrics.v1"
    private static let capacity = 60

    static func record(tool: String, seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        var values = load()
        values.append(Sample(tool: tool, seconds: seconds))
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static var summary: String {
        let values = load()
        guard !values.isEmpty else {
            return "暂无样本（完成一次设备操作后显示）"
        }
        let sorted = values.map(\.seconds).sorted()
        let p50 = sorted[max(0, min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.5).rounded())))]
        let p95 = sorted[max(0, min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.95).rounded())))]
        return String(format: "p50 %.2fs · p95 %.2fs · 样本 %d", p50, p95, sorted.count)
    }

    private static func load() -> [Sample] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Sample].self, from: data)) ?? []
    }
}

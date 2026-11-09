import Foundation
import HealthKit

@MainActor
final class HealthKitExecutor {
    private struct MetricDefinition {
        let key: String
        let type: HKQuantityType
        let unit: HKUnit
        let unitName: String
    }

    private let store = HKHealthStore()

    func summary(arguments: [String: JSONValue]) async throws -> JSONValue {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ToolExecutionError(code: "healthkit_unavailable", message: "当前设备不支持 HealthKit")
        }

        let start = try ToolDate.requiredDate(arguments, key: "startAt")
        let end = try ToolDate.requiredDate(arguments, key: "endAt")
        guard end > start else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }

        let metrics = arguments.optionalStringArray("metrics") ?? []
        guard !metrics.isEmpty else {
            throw ToolExecutionError(code: "invalid_arguments", message: "metrics 不能为空")
        }

        var definitions: [MetricDefinition] = []
        for metric in metrics {
            guard let definition = definition(for: metric) else {
                throw ToolExecutionError(code: "unsupported_metric", message: "不支持的健康指标 \(metric)")
            }
            definitions.append(definition)
        }

        var values: [String: JSONValue] = [:]
        var hasData = false
        for definition in definitions {
            let value = try await sum(definition: definition, start: start, end: end)
            if let value {
                hasData = true
                values[definition.key] = .object([
                    "value": .number((value * 10).rounded() / 10),
                    "unit": .string(definition.unitName)
                ])
            } else {
                values[definition.key] = .null
            }
        }

        var payload: [String: JSONValue] = [
            "state": .string(hasData ? "ok" : "no_data"),
            "metrics": .object(values),
            "source": .string("healthkit"),
            "simulated": .bool(false)
        ]
        if !hasData {
            payload["note"] = .string("HealthKit 没有返回数据；可能是该区间无记录，或读权限被拒绝，系统不披露读权限状态")
        }
        return .object(payload)
    }

    private func definition(for key: String) -> MetricDefinition? {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let unitName: String
        switch key {
        case "steps":
            identifier = .stepCount
            unit = .count()
            unitName = "步"
        case "activeEnergy":
            identifier = .activeEnergyBurned
            unit = .kilocalorie()
            unitName = "千卡"
        case "exerciseMinutes":
            identifier = .appleExerciseTime
            unit = .minute()
            unitName = "分钟"
        case "distance":
            identifier = .distanceWalkingRunning
            unit = .meter()
            unitName = "米"
        default:
            return nil
        }
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return MetricDefinition(key: key, type: type, unit: unit, unitName: unitName)
    }

    private func sum(definition: MetricDefinition, start: Date, end: Date) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(
                quantityType: definition.type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let quantity = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: quantity.doubleValue(for: definition.unit))
            }
            store.execute(query)
        }
    }
}

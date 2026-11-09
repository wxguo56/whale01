import CoreLocation
import Foundation
import WeatherKit

@MainActor
final class WeatherExecutor {
    func query(arguments: [String: JSONValue]) async throws -> JSONValue {
        let locationName = try arguments.requiredString("locationName")
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier
        let start = try ToolDate.requiredDate(arguments, key: "startAt")
        let end = try ToolDate.requiredDate(arguments, key: "endAt")
        guard end > start else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }

        let region = arguments.optionalString("region")
        let query = [region, locationName].compactMap { $0 }.joined(separator: " ")
        let location = try await geocode(query)

        let forecast: Forecast<DayWeather>
        do {
            forecast = try await WeatherService.shared.weather(
                for: location,
                including: .daily(startDate: start, endDate: end)
            )
        } catch {
            throw ToolExecutionError(
                code: "weatherkit_unavailable",
                message: "WeatherKit 请求失败：\(error.localizedDescription)。请确认 Apple Developer 团队已启用 WeatherKit 能力并联网。"
            )
        }

        guard let day = forecast.forecast.first else {
            return .object([
                "locationName": .string(locationName),
                "state": .string("no_data"),
                "note": .string("WeatherKit 在该区间没有预报数据"),
                "source": .string("weatherkit"),
                "simulated": .bool(false)
            ])
        }

        let high = day.highTemperature.converted(to: .celsius).value
        let low = day.lowTemperature.converted(to: .celsius).value
        let chance = max(0, min(1, day.precipitationChance))
        let rawCondition = String(describing: day.condition)
        let conditionKey = rawCondition.split(separator: ".").last.map(String.init) ?? rawCondition
        let summary = chineseSummary(conditionKey)

        var advice = "暂无强降雨信号"
        if chance >= 0.5 {
            advice = "降水概率较高，建议带伞"
        }
        if high >= 30 {
            advice = "气温较高，注意防晒补水"
        }

        return .object([
            "locationName": .string(locationName),
            "date": .string(ToolDate.day(day.date, timezone: timezone)),
            "condition": .string(conditionKey),
            "summary": .string(summary),
            "temperatureC": .object([
                "min": .number((low * 10).rounded() / 10),
                "max": .number((high * 10).rounded() / 10)
            ]),
            "precipitationChance": .number((chance * 100).rounded()),
            "advice": .string(advice),
            "source": .string("weatherkit"),
            "simulated": .bool(false)
        ])
    }

    private func geocode(_ query: String) async throws -> CLLocation {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(query) { placemarks, error in
                if let error {
                    continuation.resume(
                        throwing: ToolExecutionError(
                            code: "geocode_failed",
                            message: "无法定位 \(query)：\(error.localizedDescription)"
                        )
                    )
                    return
                }
                guard let location = placemarks?.first?.location else {
                    continuation.resume(
                        throwing: ToolExecutionError(code: "geocode_failed", message: "没有找到 \(query) 的位置")
                    )
                    return
                }
                continuation.resume(returning: location)
            }
        }
    }

    private func chineseSummary(_ raw: String) -> String {
        switch raw {
        case "clear": return "晴"
        case "mostlyClear": return "晴间多云"
        case "partlyCloudy": return "局部多云"
        case "mostlyCloudy": return "多云"
        case "cloudy": return "阴"
        case "rain": return "雨"
        case "drizzle": return "小雨"
        case "heavyRain": return "大雨"
        case "snow": return "雪"
        case "foggy": return "雾"
        case "haze": return "霾"
        case "windy": return "大风"
        case "thunderstorms": return "雷雨"
        default: return raw
        }
    }
}

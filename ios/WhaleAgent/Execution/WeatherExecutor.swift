import CoreLocation
import Foundation

/// Queries the public Open-Meteo forecast API.
///
/// This path needs no Apple entitlement, so a free-signed sideload build can
/// still read real temperatures. Nothing here invents a temperature: when the
/// provider fails the call throws and the caller must say so.
@MainActor
final class WeatherExecutor {
    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let time: String?
            let temperature2m: Double?
            let apparentTemperature: Double?
            let relativeHumidity2m: Double?
            let precipitation: Double?
            let weatherCode: Int?
            let windSpeed10m: Double?
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case precipitation
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let time: [String]?
            let temperature2m: [Double?]?
            let apparentTemperature: [Double?]?
            let precipitationProbability: [Double?]?
            let weatherCode: [Int?]?
            let isDay: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case precipitationProbability = "precipitation_probability"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let time: [String]?
            let weatherCode: [Int?]?
            let temperatureMax: [Double?]?
            let temperatureMin: [Double?]?
            let precipitationChance: [Double?]?
            let uvIndexMax: [Double?]?
            let sunrise: [String]?
            let sunset: [String]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
                case precipitationChance = "precipitation_probability_max"
                case uvIndexMax = "uv_index_max"
                case sunrise
                case sunset
            }
        }

        let timezone: String?
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?
    }

    private struct AirQualityResponse: Decodable {
        struct Current: Decodable {
            let time: String?
            let usAqi: Double?
            let pm25: Double?
            let pm10: Double?

            enum CodingKeys: String, CodingKey {
                case time
                case usAqi = "us_aqi"
                case pm25 = "pm2_5"
                case pm10
            }
        }

        let current: Current?
    }

    private struct WttrResponse: Decodable {
        struct Current: Decodable {
            let tempC: String?
            let feelsLikeC: String?
            let humidity: String?
            let precipMM: String?
            let windspeedKmph: String?
            let weatherCode: String?

            enum CodingKeys: String, CodingKey {
                case tempC = "temp_C"
                case feelsLikeC = "FeelsLikeC"
                case humidity, precipMM, windspeedKmph, weatherCode
            }
        }

        struct Astronomy: Decodable {
            let sunrise: String?
            let sunset: String?
        }

        struct Hourly: Decodable {
            let time: String?
            let tempC: String?
            let feelsLikeC: String?
            let weatherCode: String?
            let chanceofrain: String?

            enum CodingKeys: String, CodingKey {
                case time
                case tempC = "tempC"
                case feelsLikeC = "FeelsLikeC"
                case weatherCode, chanceofrain
            }
        }

        struct Day: Decodable {
            let date: String?
            let maxtempC: String?
            let mintempC: String?
            let astronomy: [Astronomy]?
            let hourly: [Hourly]?
        }

        let currentCondition: [Current]?
        let weather: [Day]?

        enum CodingKeys: String, CodingKey {
            case currentCondition = "current_condition"
            case weather
        }
    }
    private struct ResolvedLocation {
        let coordinate: CLLocationCoordinate2D
        let name: String
        let source: String
    }

    private let session: URLSession
    private let locationProvider = CurrentLocationProvider()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func query(arguments: [String: JSONValue]) async throws -> JSONValue {
        let timezone = arguments.optionalString("timezone") ?? TimeZone.current.identifier
        let start = try ToolDate.requiredDate(arguments, key: "startAt")
        let end = try ToolDate.requiredDate(arguments, key: "endAt")
        guard end >= start else {
            throw ToolExecutionError(code: "invalid_time_range", message: "结束时间必须晚于开始时间")
        }

        let requested = (arguments.optionalString("locationName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let region = (arguments.optionalString("region") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let target: ResolvedLocation
        if requested.isEmpty {
            target = try await deviceLocation()
        } else {
            let query = [region, requested].filter { !$0.isEmpty }.joined(separator: " ")
            target = try await geocodedLocation(query: query)
        }

        let startDay = ToolDate.day(start, timezone: timezone)
        let endDay = ToolDate.day(end, timezone: timezone)
        guard Self.daySpan(from: startDay, to: endDay) <= 16 else {
            throw ToolExecutionError(
                code: "weather_range_unsupported",
                message: "公共天气接口只提供未来 16 天内的逐日预报；请缩小查询区间。"
            )
        }

        var payload: [String: JSONValue]
        do {
            payload = try await fetchForecast(
                latitude: target.coordinate.latitude,
                longitude: target.coordinate.longitude,
                startDay: startDay,
                endDay: endDay
            )
        } catch {
            let primary = error.localizedDescription
            do {
                payload = try await fetchFallbackForecast(
                    latitude: target.coordinate.latitude,
                    longitude: target.coordinate.longitude
                )
            } catch {
                throw ToolExecutionError(
                    code: "weather_provider_unavailable",
                    message: "天气接口均不可用：Open-Meteo \(primary)；备用源 \(error.localizedDescription)"
                )
            }
        }
        if let air = try? await fetchAirQuality(
            latitude: target.coordinate.latitude,
            longitude: target.coordinate.longitude
        ) {
            payload["airQuality"] = air
        }
        payload["locationName"] = .string(target.name)
        payload["locationSource"] = .string(target.source)
        payload["latitude"] = .number(target.coordinate.latitude)
        payload["longitude"] = .number(target.coordinate.longitude)
        payload["requestedTimezone"] = .string(timezone)
        payload["fetchedAt"] = .string(ToolDate.iso(Date()))
        if payload["source"] == nil { payload["source"] = .string("open-meteo") }
        payload["simulated"] = .bool(false)
        if payload["note"] == nil { payload["note"] = .string("天气来自 Open-Meteo 公共预报接口；不同供应商的预报会有差异，以本轮返回值为准。") }
        return .object(payload)
    }

    // MARK: - Provider

    private func fetchForecast(
        latitude: Double,
        longitude: Double,
        startDay: String,
        endDay: String
    ) async throws -> [String: JSONValue] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset"
            ),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,is_day"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,apparent_temperature,precipitation_probability,weather_code,is_day"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: startDay),
            URLQueryItem(name: "end_date", value: endDay),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components?.url else {
            throw ToolExecutionError(code: "invalid_query", message: "无法生成天气请求地址")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("WhaleAgent/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ToolExecutionError(
                code: "weather_provider_unavailable",
                message: "公共天气接口请求失败：\(error.localizedDescription)。本次没有天气数据，请稍后重试。"
            )
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ToolExecutionError(
                code: "weather_provider_unavailable",
                message: "公共天气接口返回 HTTP \(http.statusCode)，本次没有天气数据。"
            )
        }
        return try Self.parseForecast(data: data)
    }

    private func fetchFallbackForecast(latitude: Double, longitude: Double) async throws -> [String: JSONValue] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wttr.in"
        components.path = String(format: "/%.4f,%.4f", latitude, longitude)
        components.queryItems = [URLQueryItem(name: "format", value: "j1")]
        guard let url = components.url else {
            throw ToolExecutionError(code: "invalid_query", message: "无法生成备用天气请求地址")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("WhaleAgent/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ToolExecutionError(
                code: "weather_fallback_unavailable",
                message: "备用天气接口请求失败：\(error.localizedDescription)"
            )
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ToolExecutionError(
                code: "weather_fallback_unavailable",
                message: "备用天气接口返回 HTTP \(http.statusCode)"
            )
        }
        return try Self.parseFallback(data: data)
    }

    static func parseFallback(data: Data) throws -> [String: JSONValue] {
        let decoded: WttrResponse
        do {
            decoded = try JSONDecoder().decode(WttrResponse.self, from: data)
        } catch {
            throw ToolExecutionError(
                code: "weather_fallback_invalid",
                message: "备用天气接口返回了无法解析的数据：\(error.localizedDescription)"
            )
        }
        guard let rawDays = decoded.weather, !rawDays.isEmpty else {
            throw ToolExecutionError(code: "weather_fallback_no_data", message: "备用天气接口没有返回逐日预报。")
        }

        var days: [JSONValue] = []
        for day in rawDays {
            guard let date = day.date else { continue }
            let firstCode = day.hourly?.compactMap { Int($0.weatherCode ?? "") }.first ?? 113
            let wmo = wmoEquivalent(forWWO: firstCode)
            let high = day.maxtempC.flatMap(Double.init)
            let low = day.mintempC.flatMap(Double.init)
            let chance = day.hourly?.compactMap { Double($0.chanceofrain ?? "") }.max()
            let astro = day.astronomy?.first
            let row: [String: JSONValue] = [
                "date": .string(date),
                "condition": .string(conditionKey(for: wmo)),
                "summary": .string(summary(for: wmo)),
                "temperatureC": .object([
                    "min": low.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                    "max": high.map { JSONValue.number(round1($0)) } ?? JSONValue.null
                ]),
                "precipitationChance": chance.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "uvIndexMax": .null,
                "sunrise": astro?.sunrise.map { JSONValue.string($0) } ?? JSONValue.null,
                "sunset": astro?.sunset.map { JSONValue.string($0) } ?? JSONValue.null,
                "advice": .string(advice(high: high, low: low, chance: chance, code: wmo))
            ]
            days.append(.object(row))
        }
        guard var payload = days.first?.objectValue else {
            throw ToolExecutionError(code: "weather_fallback_no_data", message: "备用天气接口没有可用的逐日预报。")
        }
        payload["days"] = .array(days)
        payload["dayCount"] = .number(Double(days.count))
        payload["timezone"] = .string(TimeZone.current.identifier)
        payload["source"] = .string("wttr.in")
        payload["note"] = .string("Open-Meteo 在当前网络不可达，已回退到 wttr.in 公共天气接口；逐日预报为 3 天。")
        if let astro = rawDays.first?.astronomy?.first,
           let sunrise = astro.sunrise, let sunset = astro.sunset {
            payload["sun"] = .object([
                "sunrise": JSONValue.string(sunrise),
                "sunset": JSONValue.string(sunset)
            ])
        }

        let hour = Calendar.current.component(.hour, from: Date())
        if let current = decoded.currentCondition?.first {
            let code = Int(current.weatherCode ?? "") ?? 113
            let wmo = wmoEquivalent(forWWO: code)
            payload["current"] = .object([
                "time": .string(ToolDate.iso(Date())),
                "temperatureC": numberValue(current.tempC),
                "apparentC": numberValue(current.feelsLikeC),
                "humidity": numberValue(current.humidity),
                "precipitationMM": numberValue(current.precipMM),
                "windKph": numberValue(current.windspeedKmph),
                "condition": .string(conditionKey(for: wmo)),
                "summary": .string(summary(for: wmo)),
                "isDay": .bool((6..<19).contains(hour))
            ])
        }

        var hours: [JSONValue] = []
        for (dayIndex, day) in rawDays.enumerated() {
            guard let date = day.date else { continue }
            for slot in day.hourly ?? [] {
                guard let raw = slot.time, let stamp = Int(raw) else { continue }
                let slotHour = stamp / 100
                if dayIndex == 0 && slotHour < hour { continue }
                let code = Int(slot.weatherCode ?? "") ?? 113
                let wmo = wmoEquivalent(forWWO: code)
                let time = String(format: "%@T%02d:00", date, slotHour)
                hours.append(.object([
                    "time": .string(time),
                    "temperatureC": numberValue(slot.tempC),
                    "apparentC": numberValue(slot.feelsLikeC),
                    "precipitationChance": numberValue(slot.chanceofrain),
                    "condition": .string(conditionKey(for: wmo)),
                    "summary": .string(summary(for: wmo)),
                    "isDay": .bool((6..<19).contains(slotHour))
                ]))
                if hours.count >= 24 { break }
            }
            if hours.count >= 24 { break }
        }
        if !hours.isEmpty { payload["hourly"] = .array(hours) }
        return payload
    }

    private static func numberValue(_ text: String?) -> JSONValue {
        guard let text, let value = Double(text) else { return .null }
        return .number(round1(value))
    }

    static func wmoEquivalent(forWWO code: Int?) -> Int {
        guard let code else { return 3 }
        switch code {
        case 113: return 0
        case 116: return 2
        case 119, 122: return 3
        case 143, 248, 260: return 45
        case 176, 263, 266, 293, 296: return 61
        case 299, 302: return 63
        case 305, 308: return 65
        case 311, 314, 317, 320: return 67
        case 323, 326: return 71
        case 329, 332: return 73
        case 335, 338: return 75
        case 350, 374, 377: return 77
        case 353, 356: return 80
        case 359, 362: return 81
        case 365, 368: return 85
        case 371: return 86
        case 386, 389: return 95
        case 392, 395: return 96
        default: return 3
        }
    }
    private func fetchAirQuality(latitude: Double, longitude: Double) async throws -> JSONValue {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else {
            throw ToolExecutionError(code: "invalid_query", message: "无法生成空气质量请求地址")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("WhaleAgent/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ToolExecutionError(code: "air_quality_unavailable", message: "空气质量接口返回 HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(AirQualityResponse.self, from: data)
        guard let current = decoded.current else {
            throw ToolExecutionError(code: "air_quality_no_data", message: "空气质量接口没有返回当前数据")
        }
        return .object([
            "time": current.time.map { JSONValue.string($0) } ?? JSONValue.null,
            "usAqi": current.usAqi.map { JSONValue.number(Self.round1($0)) } ?? JSONValue.null,
            "pm25": current.pm25.map { JSONValue.number(Self.round1($0)) } ?? JSONValue.null,
            "pm10": current.pm10.map { JSONValue.number(Self.round1($0)) } ?? JSONValue.null
        ])
    }

    static func parseForecast(data: Data) throws -> [String: JSONValue] {
        let decoded: OpenMeteoResponse
        do {
            decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw ToolExecutionError(
                code: "weather_payload_invalid",
                message: "公共天气接口返回了无法解析的数据：\(error.localizedDescription)"
            )
        }

        guard let daily = decoded.daily,
              let dates = daily.time,
              !dates.isEmpty else {
            throw ToolExecutionError(code: "weather_no_data", message: "公共天气接口在该区间没有返回逐日预报。")
        }
        let codes = daily.weatherCode ?? []
        let maximums = daily.temperatureMax ?? []
        let minimums = daily.temperatureMin ?? []
        let chances = daily.precipitationChance ?? []
        let uvs = daily.uvIndexMax ?? []
        let sunrises = daily.sunrise ?? []
        let sunsets = daily.sunset ?? []

        func value<T>(_ list: [T?], _ index: Int) -> T? {
            guard index < list.count else { return nil }
            return list[index]
        }

        var days: [JSONValue] = []
        for (index, date) in dates.enumerated() {
            let code = value(codes, index)
            let high = value(maximums, index)
            let low = value(minimums, index)
            let chance = value(chances, index)
            let row: [String: JSONValue] = [
                "date": .string(date),
                "condition": .string(conditionKey(for: code)),
                "summary": .string(summary(for: code)),
                "temperatureC": .object([
                    "min": low.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                    "max": high.map { JSONValue.number(round1($0)) } ?? JSONValue.null
                ]),
                "precipitationChance": chance.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "uvIndexMax": value(uvs, index).map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "sunrise": value(sunrises, index).map { JSONValue.string($0) } ?? JSONValue.null,
                "sunset": value(sunsets, index).map { JSONValue.string($0) } ?? JSONValue.null,
                "advice": .string(advice(high: high, low: low, chance: chance, code: code))
            ]
            days.append(.object(row))
        }

        guard var payload = days.first?.objectValue else {
            throw ToolExecutionError(code: "weather_no_data", message: "公共天气接口在该区间没有返回逐日预报。")
        }
        payload["days"] = .array(days)
        payload["dayCount"] = .number(Double(days.count))
        payload["timezone"] = decoded.timezone.map { JSONValue.string($0) } ?? JSONValue.null
        if let sunrise = sunrises.first, let sunset = sunsets.first {
            payload["sun"] = .object([
                "sunrise": .string(sunrise),
                "sunset": .string(sunset)
            ])
        }
        if let current = decoded.current {
            payload["current"] = .object([
                "time": current.time.map { JSONValue.string($0) } ?? JSONValue.null,
                "temperatureC": current.temperature2m.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "apparentC": current.apparentTemperature.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "humidity": current.relativeHumidity2m.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "precipitationMM": current.precipitation.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "windKph": current.windSpeed10m.map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                "condition": .string(conditionKey(for: current.weatherCode)),
                "summary": .string(summary(for: current.weatherCode)),
                "isDay": .bool((current.isDay ?? 1) == 1)
            ])
        }
        if let hourly = decoded.hourly,
           let times = hourly.time, !times.isEmpty {
            let currentTime = decoded.current?.time ?? ""
            let startIndex = times.firstIndex { currentTime.isEmpty || $0 >= currentTime } ?? 0
            let temperatures = hourly.temperature2m ?? []
            let apparents = hourly.apparentTemperature ?? []
            let probabilities = hourly.precipitationProbability ?? []
            let codesHourly = hourly.weatherCode ?? []
            let daylight = hourly.isDay ?? []

            var hours: [JSONValue] = []
            for index in startIndex..<min(times.count, startIndex + 24) {
                let code = value(codesHourly, index)
                let row: [String: JSONValue] = [
                    "time": .string(times[index]),
                    "temperatureC": value(temperatures, index).map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                    "apparentC": value(apparents, index).map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                    "precipitationChance": value(probabilities, index).map { JSONValue.number(round1($0)) } ?? JSONValue.null,
                    "condition": .string(conditionKey(for: code)),
                    "summary": .string(summary(for: code)),
                    "isDay": .bool((value(daylight, index) ?? 1) == 1)
                ]
                hours.append(.object(row))
            }
            payload["hourly"] = .array(hours)
        }
        return payload
    }

    // MARK: - Location

    private func deviceLocation() async throws -> ResolvedLocation {
        let location = try await locationProvider.currentLocation()
        let name = await reverseName(location) ?? "当前位置"
        return ResolvedLocation(coordinate: location.coordinate, name: name, source: "device")
    }

    private func reverseName(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? LocationExecutor.displayAddress(placemark)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
        }
    }

    private func geocodedLocation(query: String) async throws -> ResolvedLocation {
        let geocoder = CLGeocoder()
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.geocodeAddressString(query)
        } catch {
            throw ToolExecutionError(code: "geocode_failed", message: "无法定位 \(query)：\(error.localizedDescription)")
        }
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw ToolExecutionError(code: "geocode_failed", message: "没有找到 \(query) 的位置")
        }
        let display = LocationExecutor.displayAddress(placemark)
        return ResolvedLocation(
            coordinate: location.coordinate,
            name: display.isEmpty ? query : display,
            source: "geocoded"
        )
    }

    // MARK: - WMO mapping

    static func summary(for code: Int?) -> String {
        guard let code else { return "未知" }
        switch code {
        case 0: return "晴"
        case 1: return "大部晴朗"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51: return "小毛毛雨"
        case 53: return "毛毛雨"
        case 55: return "强毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "米雪"
        case 80: return "小阵雨"
        case 81: return "中阵雨"
        case 82: return "强阵雨"
        case 85: return "小阵雪"
        case 86: return "大阵雪"
        case 95: return "雷雨"
        case 96, 99: return "雷雨伴冰雹"
        default: return "天气代码 \(code)"
        }
    }

    static func conditionKey(for code: Int?) -> String {
        guard let code else { return "unknown" }
        switch code {
        case 0, 1: return "clear"
        case 2: return "partlyCloudy"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51, 53, 55, 56, 57: return "drizzle"
        case 61, 63: return "rain"
        case 65, 66, 67: return "heavyRain"
        case 71, 73, 75, 77, 85, 86: return "snow"
        case 80, 81, 82: return "showers"
        case 95, 96, 99: return "thunderstorm"
        default: return "unknown"
        }
    }

    static func advice(high: Double?, low: Double?, chance: Double?, code: Int?) -> String {
        var notes: [String] = []
        if let chance, chance >= 30 {
            notes.append("降水概率 \(Int(chance.rounded()))%，建议带伞")
        } else if let code, [61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99].contains(code) {
            notes.append("预报有降水，建议带伞")
        }
        if let high, high >= 30 {
            notes.append("最高 \(Int(high.rounded()))℃，注意防晒补水")
        }
        if let low, low <= 5 {
            notes.append("最低 \(Int(low.rounded()))℃，注意保暖")
        }
        if let code, [95, 96, 99].contains(code) {
            notes.append("有雷雨，尽量避免户外活动")
        }
        return notes.isEmpty ? "暂无明显降水或极端气温信号" : notes.joined(separator: "；")
    }

    static func daySpan(from startDay: String, to endDay: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        formatter.timeZone = utc
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let start = formatter.date(from: startDay),
              let end = formatter.date(from: endDay) else {
            return Int.max
        }
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? Int.max
        return days + 1
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

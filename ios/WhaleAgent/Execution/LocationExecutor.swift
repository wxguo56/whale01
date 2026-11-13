import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationExecutor {
    private let locationProvider = CurrentLocationProvider()

    func currentPlace(arguments: [String: JSONValue]) async throws -> JSONValue {
        let location = try await locationProvider.currentLocation()
        let locatedAt = ToolDate.iso(location.timestamp)

        do {
            let placemark = try await reverseGeocode(location)
            let displayAddress = Self.displayAddress(placemark)
            return .object([
                "displayAddress": .string(displayAddress.isEmpty ? "已取得坐标，但系统没有解析出地址" : displayAddress),
                "name": placemark.name.map { JSONValue.string($0) } ?? .null,
                "street": placemark.thoroughfare.map { JSONValue.string($0) } ?? .null,
                "district": placemark.subLocality.map { JSONValue.string($0) } ?? .null,
                "city": placemark.locality.map { JSONValue.string($0) } ?? .null,
                "province": placemark.administrativeArea.map { JSONValue.string($0) } ?? .null,
                "country": placemark.country.map { JSONValue.string($0) } ?? .null,
                "latitude": .number(location.coordinate.latitude),
                "longitude": .number(location.coordinate.longitude),
                "accuracyMeters": .number(location.horizontalAccuracy.rounded()),
                "locatedAt": .string(locatedAt),
                "addressResolved": .bool(!displayAddress.isEmpty),
                "source": .string("corelocation"),
                "simulated": .bool(false),
                "note": .string("位置来自手机本次定位，精度约 \(Int(location.horizontalAccuracy.rounded())) 米；地址由系统反向地理编码得到。")
            ])
        } catch {
            return .object([
                "displayAddress": .null,
                "latitude": .number(location.coordinate.latitude),
                "longitude": .number(location.coordinate.longitude),
                "accuracyMeters": .number(location.horizontalAccuracy.rounded()),
                "locatedAt": .string(locatedAt),
                "addressResolved": .bool(false),
                "source": .string("corelocation"),
                "simulated": .bool(false),
                "note": .string("已取得手机坐标，但反向地理编码失败：\(error.localizedDescription)。只能说明坐标和精度，不要编造街道或城市。")
            ])
        }
    }

    static func displayAddress(_ placemark: CLPlacemark) -> String {
        displayAddress(
            region: [placemark.administrativeArea, placemark.locality, placemark.subLocality],
            detail: [placemark.thoroughfare, placemark.name]
        )
    }

    static func displayAddress(region: [String?], detail: [String?]) -> String {
        var seen = Set<String>()
        let regionParts = region
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let detailParts = detail
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let regionText = regionParts.joined()
        return ([regionText] + detailParts).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let placemark = placemarks?.first else {
                    continuation.resume(
                        throwing: ToolExecutionError(code: "reverse_geocode_empty", message: "没有解析出当前位置地址")
                    )
                    return
                }
                continuation.resume(returning: placemark)
            }
        }
    }

    func searchPlaces(arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let limit = min(max(arguments.optionalInt("limit") ?? 5, 1), 25)
        let explicitRadius = arguments.optionalInt("radiusMeters").map { min(max($0, 100), 50_000) }

        let near = arguments.optionalObject("near")
        let region = arguments.optionalString("region")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = arguments.optionalString("locationMode")
            ?? (near != nil ? "provided" : ((region?.isEmpty == false) ? "region" : "current"))
        guard ["current", "region", "provided"].contains(mode) else {
            throw ToolExecutionError(code: "invalid_arguments", message: "locationMode 必须是 current、region 或 provided")
        }

        let center: CLLocation
        switch mode {
        case "provided":
            guard let near,
                  let latitude = near.optionalDouble("latitude"),
                  let longitude = near.optionalDouble("longitude") else {
                throw ToolExecutionError(code: "invalid_arguments", message: "locationMode=provided 时必须提供 near 经纬度")
            }
            center = CLLocation(latitude: latitude, longitude: longitude)
        case "region":
            guard let region, !region.isEmpty else {
                throw ToolExecutionError(code: "invalid_arguments", message: "locationMode=region 时必须提供 region")
            }
            center = try await geocode(region)
        default:
            center = try await locationProvider.currentLocation()
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        let searchRadius = Double(explicitRadius ?? 5_000)
        request.region = MKCoordinateRegion(
            center: center.coordinate,
            latitudinalMeters: max(searchRadius * 2.4, 1_200),
            longitudinalMeters: max(searchRadius * 2.4, 1_200)
        )

        let response = try await search(request)
        let candidates: [(item: MKMapItem, distance: CLLocationDistance)] = response.mapItems.map { item in
            let target = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            return (item, center.distance(from: target))
        }
        let filtered = explicitRadius.map { radius in
            candidates.filter { $0.distance <= Double(radius) }
        } ?? candidates
        let selected = Array(filtered.sorted { $0.distance < $1.distance }.prefix(limit))

        let places: [JSONValue] = selected.map { entry in
            let item = entry.item
            let placeId = PlaceStore.shared.store(item)
            var row: [String: JSONValue] = [
                "placeId": .string(placeId),
                "name": .string(item.name ?? "未命名地点"),
                "category": item.pointOfInterestCategory.map { JSONValue.string($0.rawValue) } ?? .null,
                "address": item.placemark.title.map { JSONValue.string($0) } ?? .null,
                "latitude": .number(item.placemark.coordinate.latitude),
                "longitude": .number(item.placemark.coordinate.longitude),
                "distanceMeters": .number(entry.distance.rounded())
            ]
            if let phone = item.phoneNumber {
                row["phone"] = .string(phone)
            }
            return .object(row)
        }

        return .object([
            "query": .string(query),
            "places": .array(places),
            "count": .number(Double(places.count)),
            "candidatePoolCount": .number(Double(candidates.count)),
            "locationMode": .string(mode),
            "radiusMeters": explicitRadius.map { JSONValue.number(Double($0)) } ?? .null,
            "radiusApplied": .bool(explicitRadius != nil),
            "distanceType": .string("straight_line"),
            "fetchedAt": .string(ToolDate.iso(Date())),
            "source": .string("mapkit"),
            "simulated": .bool(false),
            "note": .string("搜索中心只在本机使用，不回传原始坐标；distanceMeters 为搜索中心到候选的直线距离；radiusApplied=true 时已按半径过滤并排序。")
        ])
    }

    func openNavigation(arguments: [String: JSONValue]) throws -> JSONValue {
        let placeId = try arguments.requiredString("placeId")
        guard let item = PlaceStore.shared.item(for: placeId) else {
            throw ToolExecutionError(code: "unknown_place", message: "地点引用不存在或已过期，请重新搜索")
        }

        let mode = arguments.optionalString("mode") ?? "walking"
        let directionsMode: String
        switch mode {
        case "driving":
            directionsMode = MKLaunchOptionsDirectionsModeDriving
        case "transit":
            directionsMode = MKLaunchOptionsDirectionsModeTransit
        default:
            directionsMode = MKLaunchOptionsDirectionsModeWalking
        }

        let launchOptions: [String: Any] = [MKLaunchOptionsDirectionsModeKey: directionsMode]
        let opened = item.openInMaps(launchOptions: launchOptions)
        guard opened else {
            throw ToolExecutionError(code: "map_open_failed", message: "系统没有打开地图")
        }

        return .object([
            "handoff": .string("opened_map"),
            "placeId": .string(placeId),
            "mode": .string(mode),
            "opened": .bool(true),
            "openedAt": .string(ToolDate.iso(Date())),
            "note": .string("仅表示已把地点交给地图，未开始路线或抵达"),
            "source": .string("mapkit"),
            "simulated": .bool(false)
        ])
    }

    private func search(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        let search = MKLocalSearch(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                withExtendedLifetime(search) {
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let response else {
                        continuation.resume(
                            throwing: ToolExecutionError(code: "map_search_failed", message: "地图没有返回结果")
                        )
                        return
                    }
                    continuation.resume(returning: response)
                }
            }
        }
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
}

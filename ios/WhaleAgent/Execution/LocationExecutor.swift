import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationExecutor {
    private let locationProvider = CurrentLocationProvider()

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
            "searchCenter": .object([
                "latitude": .number(center.coordinate.latitude),
                "longitude": .number(center.coordinate.longitude)
            ]),
            "radiusMeters": explicitRadius.map { JSONValue.number(Double($0)) } ?? .null,
            "radiusApplied": .bool(explicitRadius != nil),
            "distanceType": .string("straight_line"),
            "source": .string("mapkit"),
            "simulated": .bool(false),
            "note": .string("distanceMeters 为搜索中心到候选的直线距离；radiusApplied=true 时已按半径过滤并排序。")
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

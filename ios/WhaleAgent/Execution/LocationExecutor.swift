import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationExecutor {
    func searchPlaces(arguments: [String: JSONValue]) async throws -> JSONValue {
        let query = try arguments.requiredString("query")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest

        var nearCoordinate: CLLocationCoordinate2D?
        if let near = arguments.optionalObject("near"),
           let latitude = near.optionalDouble("latitude"),
           let longitude = near.optionalDouble("longitude") {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            nearCoordinate = coordinate
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        } else if let region = arguments.optionalString("region"), !region.isEmpty {
            let geocoded = try? await geocode(region)
            if let location = geocoded {
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 12_000,
                    longitudinalMeters: 12_000
                )
            }
        }

        let response = try await search(request)
        let limit = min(max(arguments.optionalInt("limit") ?? 5, 1), 10)
        let items = Array(response.mapItems.prefix(limit))

        let places: [JSONValue] = items.map { item in
            let placeId = PlaceStore.shared.store(item)
            var row: [String: JSONValue] = [
                "placeId": .string(placeId),
                "name": .string(item.name ?? "未命名地点"),
                "category": item.pointOfInterestCategory.map { JSONValue.string($0.rawValue) } ?? .null,
                "address": item.placemark.title.map { JSONValue.string($0) } ?? .null,
                "latitude": .number(item.placemark.coordinate.latitude),
                "longitude": .number(item.placemark.coordinate.longitude)
            ]
            if let nearCoordinate {
                let from = CLLocation(latitude: nearCoordinate.latitude, longitude: nearCoordinate.longitude)
                let to = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                row["distanceMeters"] = .number(from.distance(from: to).rounded())
            }
            if let phone = item.phoneNumber {
                row["phone"] = .string(phone)
            }
            return .object(row)
        }

        return .object([
            "query": .string(query),
            "places": .array(places),
            "count": .number(Double(places.count)),
            "source": .string("mapkit"),
            "simulated": .bool(false)
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

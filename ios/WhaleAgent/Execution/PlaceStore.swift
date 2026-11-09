import MapKit

@MainActor
final class PlaceStore {
    static let shared = PlaceStore()

    private var items: [String: MKMapItem] = [:]

    func store(_ item: MKMapItem) -> String {
        let identifier = "place_\(UUID().uuidString.prefix(8))"
        items[identifier] = item
        return identifier
    }

    func item(for identifier: String) -> MKMapItem? {
        items[identifier]
    }
}

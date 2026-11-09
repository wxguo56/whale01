import Foundation

/// A shared item handed from the Share Extension to the main app.
/// The App Group channel is preferred; the URL scheme carries a copy so the
/// sideload build (which cannot use App Groups under free signing) still works.
struct SharedItem: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let url: String?
    let title: String?
    let createdAt: Date

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasBody: Bool {
        trimmedText.count >= 20
    }
}

enum SharedInbox {
    static let appGroup = "group.com.whale01.whaleagent"
    private static let key = "pending.share.v1"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private static var store: UserDefaults {
        sharedDefaults ?? .standard
    }

    static func save(_ item: SharedItem) {
        guard let data = try? JSONEncoder().encode(item) else { return }
        store.set(data, forKey: key)
        sharedDefaults?.synchronize()
    }

    static func pending() -> SharedItem? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedItem.self, from: data)
    }

    static func clear(id: String? = nil) {
        guard let current = pending() else { return }
        if let id, current.id != id { return }
        store.removeObject(forKey: key)
        sharedDefaults?.synchronize()
    }
}
extension Notification.Name {
    static let whaleOpenChat = Notification.Name("whale.open.chat")
}
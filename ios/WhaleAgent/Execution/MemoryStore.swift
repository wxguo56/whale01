import Foundation

struct MemoryPreference: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var key: String
    var value: String
    var updatedAt: Date
}

enum MemoryStoreError: LocalizedError {
    case emptyKey
    case emptyValue
    case tooLong

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "偏好名称不能为空"
        case .emptyValue:
            return "偏好内容不能为空"
        case .tooLong:
            return "偏好名称最多 40 个字符，内容最多 500 个字符"
        }
    }
}

/// Small, explicit user preference store. It is readable by the model as
/// context, but never treated as an authorization to perform an action.
final class MemoryStore: @unchecked Sendable {
    static let shared = MemoryStore()

    private let lock = NSLock()
    private let fileURL: URL
    private var items: [MemoryPreference] = []

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = documents.appendingPathComponent("memory-preferences.json")
        load()
    }

    func list() -> [MemoryPreference] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func snapshotText() -> String {
        let values = list()
        guard !values.isEmpty else { return "暂无已保存的偏好" }
        return values.map { "- \($0.key)：\($0.value)" }.joined(separator: "\n")
    }

    @discardableResult
    func set(key rawKey: String, value rawValue: String) throws -> MemoryPreference {
        let key = normalize(rawKey)
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MemoryStoreError.emptyKey }
        guard !value.isEmpty else { throw MemoryStoreError.emptyValue }
        guard key.count <= 40, value.count <= 500 else { throw MemoryStoreError.tooLong }

        let id = key.lowercased()
        let preference = MemoryPreference(id: id, key: key, value: value, updatedAt: Date())
        lock.lock()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = preference
        } else {
            items.insert(preference, at: 0)
        }
        items.sort { $0.updatedAt > $1.updatedAt }
        saveLocked()
        lock.unlock()
        return preference
    }

    @discardableResult
    func delete(id: String) -> Bool {
        lock.lock()
        let before = items.count
        items.removeAll { $0.id == id || $0.key.lowercased() == id.lowercased() }
        let removed = items.count != before
        if removed { saveLocked() }
        lock.unlock()
        return removed
    }

    private func normalize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MemoryPreference].self, from: data) else {
            return
        }
        items = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

import Foundation

enum ChatHistoryStore {
    static let maxMessages = 300

    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("chat-history-v1.json")
    }

    static func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return Array(decoded.suffix(maxMessages))
    }

    static func save(_ messages: [ChatMessage]) {
        let clipped = Array(messages.suffix(maxMessages))
        guard let data = try? JSONEncoder().encode(clipped) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct TaskRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var goal: String
    var conversationId: String
    var status: String
    var reply: String?
    let createdAt: Date
    var updatedAt: Date
    var executionState: JSONValue? = nil
}

actor TaskRecordStore {
    static let shared = TaskRecordStore()

    private let storageKey = "whale.task.records.v1"
    private let capacity = 50
    private var records: [TaskRecord] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TaskRecord].self, from: data) {
            records = decoded
        }
    }

    func upsert(_ record: TaskRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        records.sort { $0.updatedAt > $1.updatedAt }
        if records.count > capacity {
            records.removeLast(records.count - capacity)
        }
        persist()
    }

    func list(limit: Int = 20) -> [TaskRecord] {
        Array(records.prefix(max(0, limit)))
    }

    func find(turnId: String) -> TaskRecord? {
        records.first { $0.id == turnId }
    }

    func clear() {
        records = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

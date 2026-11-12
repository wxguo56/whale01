import Foundation

/// Lightweight on-disk cache so discover channels can render the last known
/// payload immediately after a cold launch instead of showing empty skeletons.
struct DiscoverDiskCache {
    private static let folderName = "WhaleDiscoverCache"

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let url = directory?.appendingPathComponent(fileName(key)),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let url = directory?.appendingPathComponent(fileName(key)),
              let data = try? JSONEncoder().encode(value) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func fileName(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "-") + ".json"
    }
}
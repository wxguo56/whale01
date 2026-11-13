import Foundation

enum BuildIdentity {
    private static var fields: [String: Any] {
        guard let url = Bundle.main.url(forResource: "build-identity", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    static var source: String { String((fields["gitSHA"] as? String ?? "本地未标记").prefix(12)) }
    static var builtAt: String { fields["builtAt"] as? String ?? "本地未标记" }
    static var toolSummary: String { "\(fields["toolCount"] as? Int ?? 0) 项 · 直连 \(fields["directToolCount"] as? Int ?? 0) 项" }
    static var distribution: String { fields["distribution"] as? String ?? "personal" }
}

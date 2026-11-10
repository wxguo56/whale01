import Foundation

enum BackendConfig {
    static let storageKey = "whale.backendURL"
    static let apiTokenKey = "whale.apiToken"
    static let defaultBaseURL = ""

    /// Older builds stored a LAN address as the default. Treat it as stale so
    /// existing installs move to the public HTTPS endpoint after upgrading.
    private static let legacyDefaultBaseURLs: Set<String> = [
        "http://10.219.86.103:8787",
        "http://127.0.0.1:8787",
        "http://localhost:8787"
    ]

    static var authToken: String {
        if let stored = UserDefaults.standard.string(forKey: apiTokenKey), !stored.isEmpty {
            return stored
        }
        return (Bundle.main.object(forInfoDictionaryKey: "WhaleAPIToken") as? String) ?? ""
    }

    static var currentBaseURLString: String {
        let stored = (UserDefaults.standard.string(forKey: storageKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, !legacyDefaultBaseURLs.contains(stored) {
            return stored
        }
        return defaultBaseURL
    }

    static var currentBaseURL: URL? {
        URL(string: currentBaseURLString)
    }
}

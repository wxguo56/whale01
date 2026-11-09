import Foundation

enum BackendConfig {
    static let storageKey = "whale.backendURL"
    static let apiTokenKey = "whale.apiToken"
    static let defaultBaseURL = "http://10.219.86.103:8787"

    static var authToken: String {
        if let stored = UserDefaults.standard.string(forKey: apiTokenKey), !stored.isEmpty {
            return stored
        }
        return (Bundle.main.object(forInfoDictionaryKey: "WhaleAPIToken") as? String) ?? ""
    }

    static var currentBaseURLString: String {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? defaultBaseURL
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var currentBaseURL: URL? {
        URL(string: currentBaseURLString)
    }
}

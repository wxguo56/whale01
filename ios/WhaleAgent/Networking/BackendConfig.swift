import Foundation

enum BackendConfig {
    static let storageKey = "whale.backendURL"
    static let defaultBaseURL = "http://10.219.86.103:8787"

    static var currentBaseURLString: String {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? defaultBaseURL
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var currentBaseURL: URL? {
        URL(string: currentBaseURLString)
    }
}

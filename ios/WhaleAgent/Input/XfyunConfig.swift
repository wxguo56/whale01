import Foundation

struct XfyunConfig {
    let appId: String
    let apiKey: String
    let apiSecret: String

    static var current: XfyunConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            if let raw = info[key] as? String { return raw }
            return ProcessInfo.processInfo.environment[key] ?? ""
        }
        let appId = value("XFYUN_APP_ID").trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = value("XFYUN_API_KEY").trimmingCharacters(in: .whitespacesAndNewlines)
        let apiSecret = value("XFYUN_API_SECRET").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appId.isEmpty, !apiKey.isEmpty, !apiSecret.isEmpty else { return nil }
        return XfyunConfig(appId: appId, apiKey: apiKey, apiSecret: apiSecret)
    }

    static var isConfigured: Bool { current != nil }

    static var statusText: String {
        isConfigured ? "讯飞语音已配置" : "讯飞语音未配置（使用系统听写）"
    }
}
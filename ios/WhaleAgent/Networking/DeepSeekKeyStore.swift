import Foundation
import Security

enum DeepSeekKeyStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "whale.deepseek",
         kSecAttrAccount as String: "personal-api-key"]
    }
    static var value: String? {
        var fields = query
        fields[kSecReturnData as String] = true
        fields[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(fields as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolExecutionError(code: "empty_key", message: "请填写个人 API 密钥。") }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var fields = query
            fields[kSecValueData as String] = data
            fields[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(fields as CFDictionary, nil) == errSecSuccess else {
                throw ToolExecutionError(code: "keychain_failed", message: "密钥没有保存成功，请重试。")
            }
        } else if status != errSecSuccess {
            throw ToolExecutionError(code: "keychain_failed", message: "密钥没有保存成功，请重试。")
        }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw ToolExecutionError(code: "keychain_failed", message: "密钥没有删除成功，请重试。")
        }
    }
}

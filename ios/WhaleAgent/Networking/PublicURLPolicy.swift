import Foundation
import Darwin

enum PublicURLPolicy {
    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let rawHost = url.host, url.user == nil, url.password == nil,
              url.port == nil || url.port == 80 || url.port == 443 else {
            throw ToolExecutionError(code: "unsafe_url", message: "请使用不含账号密码的公开 http/https 链接。")
        }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        guard !host.isEmpty, host != "localhost", !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              host.contains(".") || host.contains(":"),
              isPublicAddress(host) else {
            throw ToolExecutionError(code: "private_url", message: "网页工具仅访问公开网站，不能读取设备或局域网地址。")
        }
    }

    static func isPublicAddress(_ address: String) -> Bool {
        let host = address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasPrefix("::ffff:") { return isPublicAddress(String(host.dropFirst(7))) }
        if host.contains(":") {
            var parsed = in6_addr()
            guard inet_pton(AF_INET6, host, &parsed) == 1 else { return false }
            let bytes = withUnsafeBytes(of: &parsed) { Array($0) }
            // Only global unicast, excluding special/documentation ranges.
            return bytes[0] & 0xe0 == 0x20 && !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.allSatisfy({ Int($0) != nil }) {
            guard parts.count == 4, parts.allSatisfy({ $0.count <= 3 && ($0 == "0" || !$0.hasPrefix("0")) }),
                  let a = Int(parts[0]), let b = Int(parts[1]), parts.allSatisfy({ (0...255).contains(Int($0) ?? -1) }) else { return false }
            return a != 0 && a != 10 && a != 127 && a < 224 && !(a == 169 && b == 254)
                && !(a == 172 && (16...31).contains(b)) && !(a == 192 && [0, 168].contains(b))
                && !(a == 100 && (64...127).contains(b)) && !(a == 198 && [18, 19, 51].contains(b))
                && !(a == 203 && b == 0)
        }
        // Reject alternate numeric literals accepted by some resolvers.
        return !host.hasPrefix("0x") && host.range(of: "^[0-9]+$", options: .regularExpression) == nil
    }

    static func validateResolved(_ url: URL) async throws {
        try validate(url)
        let host = (url.host ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        try await Task.detached {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                throw ToolExecutionError(code: "dns_failed", message: "无法解析网站地址，请稍后重试。")
            }
            defer { freeaddrinfo(first) }
            var current: UnsafeMutablePointer<addrinfo>? = first
            while let info = current {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let code = getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer,
                                       socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                guard code == 0, isPublicAddress(String(cString: buffer)) else {
                    throw ToolExecutionError(code: "private_url", message: "网站解析到非公开地址，已停止读取。")
                }
                current = info.pointee.ai_next
            }
        }.value
    }
}

final class PublicRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url else { return nil }
        do { try await PublicURLPolicy.validateResolved(url); return request }
        catch { return nil }
    }
}

import Foundation

struct ToolExecutionError: Error, LocalizedError {
    let code: String
    let message: String
    let permission: String?

    init(code: String, message: String, permission: String? = nil) {
        self.code = code
        self.message = message
        self.permission = permission
    }

    var errorDescription: String? { message }

    var status: String {
        if code == "needs_authorization" || code == "permission_denied" {
            return "needs_authorization"
        }
        return "failed"
    }
}

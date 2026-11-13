import Foundation
import CryptoKit

struct CalendarWritePreview: Equatable, Sendable {
    let detail: String
    let conflictCount: Int
    let fingerprint: String

    static func hash(_ fields: [String]) -> String {
        SHA256.hash(data: Data(fields.joined(separator: "\u{1f}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SystemRecordPresence: Equatable {
    case present
    case missing
    case unobservable

    // Even a full-access lookup can miss an identifier after account sync or
    // recurring-event identity changes. Absence alone cannot prove deletion.
    var provesDeletion: Bool { false }
}

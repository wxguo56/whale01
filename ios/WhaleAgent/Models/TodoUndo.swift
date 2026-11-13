import Foundation

enum TodoUndo {
    case added(TodoReminder)
    case completion(before: TodoReminder, after: TodoReminder)
    var expected: TodoReminder {
        switch self { case .added(let item): return item; case .completion(_, let after): return after }
    }
    func canUndo(current: TodoReminder?, now: Date, expiresAt: Date) -> Bool {
        now <= expiresAt && !expected.deduplicated && current == expected
    }
}

import Foundation

enum QuickAction: String, CaseIterable, Identifiable {
    case schedule, reminder, music, headlines, nearby
    var id: String { rawValue }
    var title: String {
        switch self {
        case .schedule: return "看看今天安排"
        case .reminder: return "记一件事"
        case .music: return "听音乐"
        case .headlines: return "看看热点"
        case .nearby: return "找附近地点"
        }
    }
    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .reminder: return "plus.circle"
        case .music: return "music.note"
        case .headlines: return "newspaper"
        case .nearby: return "mappin.and.ellipse"
        }
    }
}

enum InteractionPreferences {
    static let quickActionsKey = "whale.home.quickActions.v1"
    static func quickActions(defaults: UserDefaults = .standard) -> [QuickAction] {
        let raw = defaults.stringArray(forKey: quickActionsKey) ?? ["schedule", "reminder", "music"]
        var seen = Set<QuickAction>()
        let valid = raw.compactMap(QuickAction.init(rawValue:)).filter { seen.insert($0).inserted }
        var result = Array((valid.isEmpty ? [.schedule, .reminder, .music] : valid).prefix(3))
        for fallback in [QuickAction.schedule, .reminder, .music] where result.count < 2 && !result.contains(fallback) { result.append(fallback) }
        return result
    }
    static func setQuickActions(_ actions: [QuickAction], defaults: UserDefaults = .standard) {
        var seen = Set<QuickAction>()
        defaults.set(Array(actions.filter { seen.insert($0).inserted }.prefix(3)).map(\.rawValue), forKey: quickActionsKey)
    }
}

struct ComposerDraftStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(context: String) -> String { defaults.string(forKey: "whale.draft." + context) ?? "" }
    func save(_ text: String, context: String) {
        let key = "whale.draft." + context
        if text.isEmpty { defaults.removeObject(forKey: key) }
        else { defaults.set(String(text.prefix(12000)), forKey: key) }
    }
}

struct ConversationFollowState: Equatable {
    private(set) var nearBottom = true
    private(set) var unread = 0
    mutating func updatePosition(nearBottom value: Bool) {
        nearBottom = value
        if value { unread = 0 }
    }
    mutating func receive(_ count: Int = 1) -> Bool {
        if nearBottom { return true }
        unread += max(0, count)
        return false
    }
    mutating func follow() { nearBottom = true; unread = 0 }
}

enum NavigationHabits {
    static func restoredTab(_ raw: String?) -> AppTab {
        guard let tab = raw.flatMap(AppTab.init(rawValue:)), tab != .settings else { return .conversation }
        return tab
    }
}

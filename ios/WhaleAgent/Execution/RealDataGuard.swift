import Foundation

enum RealDataIntent: Equatable {
    case currentLocation
    case homeNavigation
    case navigation
    case weather
    case nearbyPlaces

    var requiredTool: String? {
        switch self {
        case .currentLocation:
            return "get_current_location"
        case .homeNavigation, .navigation:
            return "open_navigation"
        case .weather:
            return "get_weather"
        case .nearbyPlaces:
            return "search_places"
        }
    }
}

enum RealDataGuard {
    static func intent(for text: String) -> RealDataIntent? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if isHomeNavigation(compact) { return .homeNavigation }
        if containsAny(compact, ["我在哪", "我现在在哪", "当前位置", "这是哪里", "这里是哪", "我的位置"]) {
            return .currentLocation
        }
        if containsAny(compact, ["天气", "下雨", "带伞", "气温", "冷不冷", "热不热"]) {
            return .weather
        }
        if containsAny(compact, ["导航", "带我去", "怎么走", "路线", "带我过去", "送我过去"]) {
            return .navigation
        }
        if containsAny(compact, ["附近", "周边", "离我", "我这", "旁边"]) {
            return .nearbyPlaces
        }
        return nil
    }

    static func isHomeNavigation(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let phrases = ["导航回家", "带我回家", "送我回家", "怎么回家", "回家怎么走", "回家路线", "回家的路线"]
        if phrases.contains(where: compact.contains) { return true }
        return ["回家", "我要回家", "我想回家", "回我家"].contains(compact)
    }

    static func homeAddress(in memories: [MemoryPreference]) -> String? {
        let candidates = memories.filter { item in
            let key = item.key.lowercased()
            return key.contains("家庭地址") || key.contains("住址") || key == "家" || key.contains("home")
        }
        return candidates.map(\.value).first(where: looksLikeAddress)
    }

    static func looksLikeAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        let markers = ["省", "市", "区", "县", "镇", "乡", "街", "路", "道", "号", "巷", "弄", "村", "小区", "大厦", "楼"]
        return markers.contains { trimmed.contains($0) }
    }

    static func preflightReply(for text: String) -> String? {
        guard intent(for: text) == .homeNavigation else { return nil }
        guard homeAddress(in: MemoryStore.shared.list()) == nil else { return nil }
        return "我还不知道你的真实家庭地址，不能规划回家路线。请告诉我具体地址；也可以在设置里保存一条“家庭地址”，以后直接说回家。"
    }

    static func toolInstruction(for intent: RealDataIntent) -> String? {
        switch intent {
        case .homeNavigation:
            return "用户要求回家。必须先使用已保存的真实家庭地址或用户本轮给出的地址，通过 search_places 解析真实地点，再在用户选定后调用 open_navigation。没有地址就追问；不得把“家”当关键词搜索，不得声称已规划路线、已出发或已到家。"
        case .navigation:
            return "用户明确要求导航或路线。必须调用真实地点或导航工具；没有真实目的地就问，不得凭文字声称已规划路线、已出发或已到达。"
        case .currentLocation:
            return "用户询问当前位置。必须调用 get_current_location，并以本轮真实结果为准；没有结果就如实说明，不得猜城市或街道。"
        case .weather:
            return "用户询问天气。必须调用 get_weather，并以本轮真实结果为准；没有结果就如实说明，不得凭常识回答。"
        case .nearbyPlaces:
            return "用户询问附近地点。必须调用 search_places 并传 locationMode=current，以本轮真实结果为准；没有结果就如实说明，不得编造店名、距离或地址。"
        }
    }

    static func finalReply(for intent: RealDataIntent, usedTools: Set<String>, proposed: String) -> String {
        if isClarifying(proposed) { return proposed }
        if let required = intent.requiredTool, usedTools.contains(required) { return proposed }

        switch intent {
        case .homeNavigation:
            if usedTools.contains("search_places") {
                return "我已经从真实地图找到候选地点，但还没有把目的地交给地图，不能算已规划路线。请选定一个候选地点，或告诉我具体地址。"
            }
            return "我还不知道你的真实家庭地址，不能规划回家路线。请告诉我具体地址，或在设置里保存家庭地址。"
        case .navigation:
            if usedTools.contains("search_places") {
                return "我已经找到真实候选地点，但还没有把目的地交给地图，不能算已规划路线。请选定一个候选地点，或告诉我具体地址。"
            }
            return "这次没有拿到真实目的地，不能规划路线。请告诉我具体地点。"
        case .currentLocation:
            return "这次没有拿到手机的真实定位，我不能确认你在哪。请检查定位权限后再试。"
        case .weather:
            return "这次没有拿到真实天气数据，不能给出天气结论。请稍后重试或检查联网。"
        case .nearbyPlaces:
            return "这次没有拿到真实附近地点数据，不能给出附近结果。请检查定位权限后再试。"
        }
    }

    static func isClarifying(_ reply: String) -> Bool {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains("？") || trimmed.contains("?") || trimmed.contains("请告诉我") || trimmed.contains("请补充")
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }
}

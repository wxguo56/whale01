import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的 JSON 值")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        doubleValue.map(Int.init)
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value { return String(format: "%.0f", value) }
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "是" : "否"
        case .null:
            return "无"
        case .array(let values):
            return values.map(\.displayText).joined(separator: "、")
        case .object(let values):
            return values.keys.sorted().map { "\($0)=\(values[$0]?.displayText ?? "")" }.joined(separator: "，")
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    init(nilLiteral: ()) { self = .null }
}

extension [String: JSONValue] {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue else {
            throw ToolExecutionError(code: "invalid_arguments", message: "缺少字符串参数 \(key)")
        }
        return value
    }

    func optionalString(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func requiredDouble(_ key: String) throws -> Double {
        guard let value = self[key]?.doubleValue else {
            throw ToolExecutionError(code: "invalid_arguments", message: "缺少数字参数 \(key)")
        }
        return value
    }

    func optionalDouble(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    func optionalInt(_ key: String) -> Int? {
        self[key]?.intValue
    }

    func optionalObject(_ key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func optionalStringArray(_ key: String) -> [String]? {
        self[key]?.arrayValue?.compactMap(\.stringValue)
    }
}

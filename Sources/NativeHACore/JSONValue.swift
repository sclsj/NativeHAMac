import Foundation

public enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public extension JSONValue {
    /// Exact deterministic semantic representation used by Lovelace source
    /// identity. This is deliberately not a hash: equality of the complete
    /// canonical value is what authorizes owner reuse.
    var canonicalSemanticValue: String {
        switch self {
        case let .string(value):
            return "s\(value.utf8.count):\(value)"
        case let .int(value):
            return "i\(value);"
        case let .double(value):
            // JSON numeric equality treats signed zero as one value. Preserve
            // exact bits otherwise, but do not split stable owner identity for
            // `-0.0` versus `0.0`.
            let normalized = value == 0 ? 0.0 : value
            return "d\(normalized.bitPattern);"
        case let .bool(value):
            return value ? "b1" : "b0"
        case let .object(value):
            return "o{" + value.keys.sorted().map { key in
                "k\(key.utf8.count):\(key)" + value[key]!.canonicalSemanticValue
            }.joined() + "}"
        case let .array(value):
            return "a[" + value.map(\.canonicalSemanticValue).joined() + "]"
        case .null:
            return "n"
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

import Foundation

public enum MCPJSONValue: Codable {
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let d = try? container.decode(Double.self) { self = .number(d) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([MCPJSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: MCPJSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }

    public func toJSONObject() -> Any {
        switch self {
        case .object(let o): return o.mapValues { $0.toJSONObject() }
        case .array(let a): return a.map { $0.toJSONObject() }
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }
}

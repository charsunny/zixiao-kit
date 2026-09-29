import Foundation

/// 离线队列里一行的载荷。
///
/// 为什么不直接用 supabase-swift 的 `AnyJSON`: 队列与本地态是纯本地逻辑, 不该因为类型而依赖 Supabase 模块;
/// 测试目标也只依赖 ZixiaoCore, 用自己的值类型最干净。它是 `Encodable`, 可以原样交给 PostgREST。
public enum ZXJSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ZXJSONValue])
    case object([String: ZXJSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // 顺序要紧: JSONDecoder 不会把 1 解成 Bool, 但会把 1 解成 Double, 所以 Int 要在 Double 之前。
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([ZXJSONValue].self) { self = .array(v); return }
        self = .object(try c.decode([String: ZXJSONValue].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

extension ZXJSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: ZXJSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, ZXJSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

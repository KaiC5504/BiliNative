import Foundation

public enum LogLevel: String, Codable, Sendable {
    case debug, info, warn, error
}

public enum LogCategory: String, Codable, Sendable {
    case app, api, engine, server, player, ui
}

public enum LogValue: Codable, Sendable, Equatable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(_ value: String) { self = .string(value) }
    public init(_ value: Int) { self = .int(Int64(value)) }
    public init(_ value: Int64) { self = .int(value) }
    public init(_ value: Double) { self = .double(value) }
    public init(_ value: Bool) { self = .bool(value) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

public struct LogEvent: Codable, Sendable, Equatable {
    /// Unix time in seconds.
    public var t: Double
    public var seq: Int64
    public var session: String
    public var level: LogLevel
    public var cat: LogCategory
    public var msg: String
    public var f: [String: LogValue]

    public init(t: Double, seq: Int64, session: String, level: LogLevel, cat: LogCategory, msg: String, f: [String: LogValue]) {
        self.t = t
        self.seq = seq
        self.session = session
        self.level = level
        self.cat = cat
        self.msg = msg
        self.f = f
    }
}

import Foundation
import BiliShared

public protocol LogSink: AnyObject {
    /// Called on the logging thread; must be thread-safe and quick.
    func receive(_ event: LogEvent)
}

public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    public let session: String
    private let state = Locked<(seq: Int64, sinks: [LogSink])>((0, []))

    public init(session: String = Logger.makeSessionID()) {
        self.session = session
    }

    public static func makeSessionID() -> String {
        let hex = String(UInt64.random(in: 0...UInt64.max), radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Returns the last seq handed out before the sink joined: every later event reaches it, no earlier one does.
    @discardableResult
    public func add(_ sink: LogSink) -> Int64 {
        state.withLock { value -> Int64 in
            value.sinks.append(sink)
            return value.seq
        }
    }

    public func remove(_ sink: LogSink) {
        state.withLock { $0.sinks.removeAll { $0 === sink } }
    }

    public func log(_ level: LogLevel, _ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) {
        let (seq, sinks) = state.withLock { value -> (Int64, [LogSink]) in
            value.seq += 1
            return (value.seq, value.sinks)
        }
        guard !sinks.isEmpty else { return }
        let event = LogEvent(t: Date().timeIntervalSince1970, seq: seq, session: session, level: level, cat: cat,
                             msg: Redactor.text(msg), f: Redactor.fields(fields))
        for sink in sinks { sink.receive(event) }
    }

    public func debug(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.debug, cat, msg, fields) }
    public func info(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.info, cat, msg, fields) }
    public func warn(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.warn, cat, msg, fields) }
    public func error(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.error, cat, msg, fields) }
}

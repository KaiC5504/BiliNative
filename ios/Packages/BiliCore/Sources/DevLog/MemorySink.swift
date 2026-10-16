import BiliShared

public final class MemorySink: LogSink, @unchecked Sendable {
    private let store = Locked<[LogEvent]>([])

    public init() {}

    public func receive(_ event: LogEvent) {
        store.withLock { $0.append(event) }
    }

    public var events: [LogEvent] { store.current }
}

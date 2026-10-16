import Foundation
import BiliShared

/// Batches events and hands them to `poster` (the app's HTTP POST to the PC) every `intervalMs`.
/// Events stay buffered until a post succeeds.
public final class NetworkSink: LogSink, @unchecked Sendable {
    public typealias Poster = @Sendable (Data) async throws -> Void

    public enum State: Equatable, Sendable {
        case idle
        case connected
        case failing(String)
    }

    private let poster: Poster
    private let intervalMs: Double
    private let maxBuffered: Int
    private let batchLimit: Int
    private let buffer = Locked<[LogEvent]>([])
    private let stateBox = Locked<State>(.idle)
    private let loop = Locked<Task<Void, Never>?>(nil)
    private let encoder = JSONEncoder()
    var encodeOverride: ((LogEvent) throws -> Data)?
    public var onAcknowledged: (@Sendable (_ session: String, _ seq: Int64) -> Void)?

    public init(poster: @escaping Poster, intervalMs: Double = 500, maxBuffered: Int = 10_000, batchLimit: Int = 2_000) {
        self.poster = poster
        self.intervalMs = intervalMs
        self.maxBuffered = maxBuffered
        self.batchLimit = batchLimit
    }

    public var state: State { stateBox.current }
    public var pending: Int { buffer.current.count }

    public func receive(_ event: LogEvent) {
        enqueue([event])
    }

    public func enqueue(_ events: [LogEvent]) {
        buffer.withLock { value in
            value.append(contentsOf: events)
            if value.count > maxBuffered { value.removeFirst(value.count - maxBuffered) }
        }
    }

    public func start() {
        loop.withLock { task in
            guard task == nil else { return }
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.flushOnce()
                    try? await sleepMs(self.intervalMs)
                }
            }
        }
    }

    public func stop() {
        loop.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    @discardableResult
    public func flushOnce() async -> Bool {
        let batch = buffer.withLock { Array($0.prefix(batchLimit)) }
        guard !batch.isEmpty else { return true }
        var body = Data()
        var encoded: [LogEvent] = []
        var firstUnencodable: [String: Int64] = [:]
        for event in batch {
            guard let line = try? (encodeOverride?(event) ?? encoder.encode(event)) else {
                firstUnencodable[event.session] = min(firstUnencodable[event.session] ?? .max, event.seq)
                continue
            }
            body.append(line)
            body.append(0x0A)
            encoded.append(event)
        }
        if !encoded.isEmpty {
            do {
                try await poster(body)
            } catch {
                stateBox.withLock { $0 = .failing(String(describing: error)) }
                return false
            }
            stateBox.withLock { $0 = .connected }
        }
        // Remove by identity: the buffer may have dropped or gained events while posting.
        let done = Set(batch.map { "\($0.session)#\($0.seq)" })
        buffer.withLock { value in value.removeAll { done.contains("\($0.session)#\($0.seq)") } }
        // The watermark stops before an event that could not be sent, so a replay would still cover it.
        var latest: [String: Int64] = [:]
        for event in encoded where event.seq < (firstUnencodable[event.session] ?? .max) {
            latest[event.session] = max(latest[event.session] ?? 0, event.seq)
        }
        for (session, seq) in latest { onAcknowledged?(session, seq) }
        return true
    }
}

import Foundation
import BiliShared

/// Highest sequence number per session that the PC confirmed, so a crashed session's tail can be resent.
public final class AckStore: @unchecked Sendable {
    private let url: URL
    private let state: Locked<[String: Int64]>

    public init(url: URL) {
        self.url = url
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) }
        state = Locked(stored ?? [:])
    }

    public func lastSeq(_ session: String) -> Int64 {
        state.current[session] ?? 0
    }

    public func record(_ session: String, _ seq: Int64) {
        // Written under the lock so a slower, older snapshot cannot land after a newer one.
        state.withLock { value in
            guard seq > (value[session] ?? 0) else { return }
            value[session] = seq
            if let data = try? JSONEncoder().encode(value) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

public enum ReplayPlanner {
    /// Events the PC has not confirmed, oldest first, at most `limit` of them (the newest win). Files are read
    /// newest first and reading stops once `limit` is reached. The current session is skipped unless `current`
    /// gives the seq span to resend: after the PC's last confirmation, up to the new sink's cut.
    public static func unsent(files: [URL], currentSession: String, ack: AckStore,
                              current: (after: Int64, through: Int64)? = nil, limit: Int = .max) -> [LogEvent] {
        var chunks: [[LogEvent]] = []
        var count = 0
        for file in files.reversed() where count < limit {
            let isCurrent = sessionName(file) == currentSession
            if isCurrent, current == nil { continue }
            let events = FileSink.readEvents(file).filter { event in
                if event.session == currentSession {
                    guard let current else { return false }
                    return event.seq > current.after && event.seq <= current.through
                }
                return event.seq > ack.lastSeq(event.session)
            }
            chunks.append(events)
            count += events.count
        }
        return Array(chunks.reversed().joined().suffix(limit))
    }

    /// `<session>.jsonl` or a sealed segment `<session>.<n>.jsonl`.
    private static func sessionName(_ file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        return name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
    }
}

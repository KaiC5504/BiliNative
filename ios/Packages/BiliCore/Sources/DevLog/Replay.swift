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
        let snapshot = state.withLock { value -> [String: Int64] in
            if seq > (value[session] ?? 0) { value[session] = seq }
            return value
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url)
        }
    }
}

public enum ReplayPlanner {
    public static func unsent(files: [URL], currentSession: String, ack: AckStore) -> [LogEvent] {
        files
            .filter { $0.deletingPathExtension().lastPathComponent != currentSession }
            .flatMap { FileSink.readEvents($0) }
            .filter { $0.seq > ack.lastSeq($0.session) }
    }
}

import Foundation
import Dispatch

/// JSON-lines files per app session, pruned oldest first to stay under `maxTotalBytes`.
/// The live file `<session>.jsonl` is sealed as `<session>.<n>.jsonl` once it reaches a quarter of the
/// cap, so the live session is bounded too.
public final class FileSink: LogSink, @unchecked Sendable {
    public let directory: URL
    public let fileURL: URL
    private let session: String
    private let maxTotalBytes: Int
    private let queue = DispatchQueue(label: "devlog.filesink")
    private var handle: FileHandle?
    private var liveBytes = 0
    private var dropped = 0
    private let encoder = JSONEncoder()

    public init(directory: URL, session: String, maxTotalBytes: Int = 20 << 20) throws {
        self.directory = directory
        self.session = session
        self.maxTotalBytes = maxTotalBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(session).jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: fileURL)
        liveBytes = Int(try opened.seekToEnd())
        handle = opened
        prune()
    }

    deinit {
        try? handle?.close()
    }

    public func receive(_ event: LogEvent) {
        guard let encoded = try? encoder.encode(event) else { return }
        let line = encoded + [0x0A]
        queue.async { self.append(line) }
    }

    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    /// Oldest first.
    public func sessionFiles() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                let (left, right) = (modified(lhs), modified(rhs))
                if left != right { return left < right }
                return lhs.lastPathComponent.compare(rhs.lastPathComponent, options: .numeric) == .orderedAscending
            }
    }

    /// Concatenates every session file into one file for the share sheet.
    public func exportFile() throws -> URL {
        flush()
        let output = exportURL
        var data = Data()
        for file in sessionFiles() {
            data.append((try? Data(contentsOf: file)) ?? Data())
        }
        try data.write(to: output)
        return output
    }

    /// Deletes every session file, the live one included, and the export; logging carries on into a fresh live file.
    public func removeAllFiles() {
        queue.sync {
            try? handle?.close()
            handle = nil
            for file in sessionFiles() + [exportURL] {
                try? FileManager.default.removeItem(at: file)
            }
            openLive()
        }
    }

    public static func readEvents(_ url: URL) -> [LogEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(LogEvent.self, from: Data($0)) }
    }

    var droppedLines: Int { queue.sync { dropped } }

    func closeHandleForTesting() {
        queue.sync { try? handle?.close() }
    }

    private var rollBytes: Int { max(maxTotalBytes / 4, 1) }

    private var exportURL: URL { directory.deletingLastPathComponent().appendingPathComponent("BiliNative-logs.jsonl") }

    // A logger must never take the app down: write errors drop the line and the file is reopened next time.
    private func append(_ line: Data) {
        if liveBytes > 0, liveBytes + line.count > rollBytes { roll() }
        if handle == nil { openLive() }
        guard let handle else {
            dropped += 1
            return
        }
        do {
            try handle.write(contentsOf: line)
            liveBytes += line.count
        } catch {
            dropped += 1
            try? handle.close()
            self.handle = nil
        }
    }

    private func openLive() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        liveBytes = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func roll() {
        try? handle?.close()
        handle = nil
        let manager = FileManager.default
        var index = 1
        var sealed = directory.appendingPathComponent("\(session).\(index).jsonl")
        while manager.fileExists(atPath: sealed.path) {
            index += 1
            sealed = directory.appendingPathComponent("\(session).\(index).jsonl")
        }
        if (try? manager.moveItem(at: fileURL, to: sealed)) == nil {
            try? manager.removeItem(at: fileURL)
        }
        openLive()
        prune()
    }

    /// Leaves room for the live file to grow to `rollBytes`, so the total never exceeds the cap.
    private func prune() {
        var files = sessionFiles()
        func size(_ url: URL) -> Int {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        }
        var total = files.reduce(0) { $0 + size($1) }
        let target = maxTotalBytes - rollBytes
        while total > target, let oldest = files.first, oldest.lastPathComponent != fileURL.lastPathComponent {
            total -= size(oldest)
            try? FileManager.default.removeItem(at: oldest)
            files.removeFirst()
        }
    }
}

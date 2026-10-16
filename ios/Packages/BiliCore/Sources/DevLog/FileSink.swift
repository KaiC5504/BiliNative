import Foundation
import Dispatch

/// One JSON-lines file per app session, pruned oldest first to stay under `maxTotalBytes`.
public final class FileSink: LogSink, @unchecked Sendable {
    public let directory: URL
    public let fileURL: URL
    private let maxTotalBytes: Int
    private let queue = DispatchQueue(label: "devlog.filesink")
    private let handle: FileHandle?
    private var writtenSincePrune = 0
    private let encoder = JSONEncoder()

    public init(directory: URL, session: String, maxTotalBytes: Int = 20 << 20) throws {
        self.directory = directory
        self.maxTotalBytes = maxTotalBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(session).jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
        prune()
    }

    deinit {
        try? handle?.close()
    }

    public func receive(_ event: LogEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        queue.async {
            self.handle?.write(line)
            self.writtenSincePrune += line.count
            if self.writtenSincePrune > self.maxTotalBytes / 8 {
                self.writtenSincePrune = 0
                self.prune()
            }
        }
    }

    public func flush() {
        queue.sync { handle?.synchronizeFile() }
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
            .sorted { (modified($0), $0.lastPathComponent) < (modified($1), $1.lastPathComponent) }
    }

    /// Concatenates every session file into one file for the share sheet.
    public func exportFile() throws -> URL {
        flush()
        let output = directory.deletingLastPathComponent().appendingPathComponent("BiliNative-logs.jsonl")
        var data = Data()
        for file in sessionFiles() {
            data.append((try? Data(contentsOf: file)) ?? Data())
        }
        try data.write(to: output)
        return output
    }

    public static func readEvents(_ url: URL) -> [LogEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(LogEvent.self, from: Data($0)) }
    }

    private func prune() {
        var files = sessionFiles()
        func size(_ url: URL) -> Int {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        }
        var total = files.reduce(0) { $0 + size($1) }
        while total > maxTotalBytes, let oldest = files.first, oldest.lastPathComponent != fileURL.lastPathComponent {
            total -= size(oldest)
            try? FileManager.default.removeItem(at: oldest)
            files.removeFirst()
        }
    }
}

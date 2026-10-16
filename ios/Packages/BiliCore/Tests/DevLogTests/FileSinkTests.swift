import XCTest
@testable import DevLog

final class FileSinkTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devlog-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWritesJSONLinesAndReadsBack() throws {
        let dir = tempDir()
        let sink = try FileSink(directory: dir, session: "aaa")
        let logger = Logger(session: "aaa")
        logger.add(sink)
        logger.info(.app, "one")
        logger.info(.app, "two")
        sink.flush()
        XCTAssertEqual(FileSink.readEvents(sink.fileURL).map(\.msg), ["one", "two"])
    }

    func testPrunesOldestSessionFiles() throws {
        let dir = tempDir()
        let filler = Data(repeating: 0x41, count: 600)
        for (name, year) in [("old", 2020), ("mid", 2021)] {
            let url = dir.appendingPathComponent("\(name).jsonl")
            try filler.write(to: url)
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))!
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        _ = try FileSink(directory: dir, session: "new", maxTotalBytes: 1000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mid.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.jsonl").path))
    }

    func testReplaySkipsAcknowledgedEventsAndTheCurrentSession() throws {
        let dir = tempDir()
        let oldSink = try FileSink(directory: dir, session: "s1")
        let oldLogger = Logger(session: "s1")
        oldLogger.add(oldSink)
        oldLogger.info(.app, "a")
        oldLogger.info(.app, "b")
        oldLogger.info(.app, "c")
        oldSink.flush()

        let currentSink = try FileSink(directory: dir, session: "s2")
        let currentLogger = Logger(session: "s2")
        currentLogger.add(currentSink)
        currentLogger.info(.app, "live")
        currentSink.flush()

        let ack = AckStore(url: dir.appendingPathComponent("ack.json"))
        ack.record("s1", 2)
        let unsent = ReplayPlanner.unsent(files: currentSink.sessionFiles(), currentSession: "s2", ack: ack)
        XCTAssertEqual(unsent.map(\.msg), ["c"])
        XCTAssertEqual(AckStore(url: dir.appendingPathComponent("ack.json")).lastSeq("s1"), 2)
    }
}

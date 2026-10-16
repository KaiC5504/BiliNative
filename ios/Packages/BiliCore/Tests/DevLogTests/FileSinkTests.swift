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

    func testNonFiniteFieldDoesNotDropTheEvent() throws {
        let dir = tempDir()
        let sink = try FileSink(directory: dir, session: "nf")
        let logger = Logger(session: "nf")
        logger.add(sink)
        logger.info(.engine, "speed", ["mbps": .double(.infinity)])
        sink.flush()
        let events = FileSink.readEvents(sink.fileURL)
        XCTAssertEqual(events.map(\.msg), ["speed"])
        XCTAssertEqual(events.first?.f["mbps"], .string("inf"))
    }

    func testFailedWriteDropsTheLineAndRecovers() throws {
        let dir = tempDir()
        let sink = try FileSink(directory: dir, session: "w")
        let logger = Logger(session: "w")
        logger.add(sink)
        logger.info(.app, "before")
        sink.flush()
        sink.closeHandleForTesting()
        logger.info(.app, "lost")
        sink.flush()
        XCTAssertEqual(sink.droppedLines, 1)
        logger.info(.app, "after")
        sink.flush()
        XCTAssertEqual(FileSink.readEvents(sink.fileURL).map(\.msg), ["before", "after"])
    }

    func testLiveSessionIsRolledAndStaysUnderTheCap() throws {
        let dir = tempDir()
        let cap = 4000
        let sink = try FileSink(directory: dir, session: "big", maxTotalBytes: cap)
        let logger = Logger(session: "big")
        logger.add(sink)
        for index in 0..<300 {
            logger.info(.engine, "event-\(index)", ["pad": "xxxxxxxxxxxxxxxxxxxxxxxx"])
        }
        sink.flush()

        let files = sink.sessionFiles()
        XCTAssertGreaterThan(files.count, 1)
        let sizes = files.map { (try? Data(contentsOf: $0).count) ?? 0 }
        XCTAssertLessThanOrEqual(sizes.reduce(0, +), cap)

        let events = files.flatMap { FileSink.readEvents($0) }
        XCTAssertEqual(events.last?.msg, "event-299")
        XCTAssertNotEqual(events.first?.msg, "event-0")
        XCTAssertEqual(events.map(\.seq), Array(events[0].seq...events[events.count - 1].seq))

        let ack = AckStore(url: dir.appendingPathComponent("ack.json"))
        XCTAssertTrue(ReplayPlanner.unsent(files: files, currentSession: "big", ack: ack).isEmpty)
        XCTAssertFalse(ReplayPlanner.unsent(files: files, currentSession: "other", ack: ack).isEmpty)
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

    func testRemoveAllFilesDeletesEverySessionAndKeepsLogging() throws {
        let dir = tempDir()
        try Data("{}\n".utf8).write(to: dir.appendingPathComponent("older.jsonl"))
        let sink = try FileSink(directory: dir, session: "rm", maxTotalBytes: 4000)
        let logger = Logger(session: "rm")
        logger.add(sink)
        for index in 0..<100 {
            logger.info(.app, "before-\(index)", ["pad": "xxxxxxxxxxxxxxxxxxxxxxxx"])
        }
        let exported = try sink.exportFile()
        XCTAssertGreaterThan(sink.sessionFiles().count, 2)

        sink.removeAllFiles()
        XCTAssertEqual(sink.sessionFiles().map(\.lastPathComponent), ["rm.jsonl"])
        XCTAssertTrue(FileSink.readEvents(sink.fileURL).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))

        logger.info(.app, "after")
        sink.flush()
        XCTAssertEqual(FileSink.readEvents(sink.fileURL).map(\.msg), ["after"])
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

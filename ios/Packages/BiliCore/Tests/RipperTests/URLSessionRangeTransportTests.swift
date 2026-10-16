import XCTest
import BiliShared
import Ripper

final class URLSessionRangeTransportTests: XCTestCase {
    private var server: LoopbackServer!
    private let range = ByteRange(start: 0, end: 99_999)!

    override func setUpWithError() throws {
        server = try LoopbackServer(routes: ["/hang": .hang, "/trickle": .trickle, "/complete": .complete(100_000)])
    }

    override func tearDown() {
        server.stop()
    }

    private func eventually(_ seconds: Double = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func testStreamsA206Body() async throws {
        let response = try await URLSessionRangeTransport().fetch(server.url("/complete"), range: range)
        XCTAssertEqual(response.status, 206)
        XCTAssertEqual(response.headers["content-range"], "bytes 0-99999/100000")
        var received = 0
        for try await chunk in response.body { received += chunk.count }
        XCTAssertEqual(received, 100_000)
    }

    func testCancelWhileWaitingForTheFirstByteThrowsAndClosesTheSocket() async throws {
        let transport = URLSessionRangeTransport()
        let url = server.url("/hang")
        let fetch = Task { try await transport.fetch(url, range: range) }
        let reached = await eventually { self.server.requests("/hang") == 1 }
        XCTAssertTrue(reached)
        let cancelledAt = Date()
        fetch.cancel()
        do {
            _ = try await fetch.value
            XCTFail("a cancelled fetch returned a response")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
        let closed = await eventually { self.server.closes("/hang") == 1 }
        XCTAssertTrue(closed)
    }

    func testAlreadyCancelledTaskThrowsWithoutARequest() async throws {
        let transport = URLSessionRangeTransport()
        let url = server.url("/hang")
        let fetch = Task { () -> TransportResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.fetch(url, range: range)
        }
        do {
            _ = try await fetch.value
            XCTFail("a cancelled fetch returned a response")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(server.requests("/hang"), 0)
    }

    func testCancelMidBodyEndsTheReadAndClosesTheSocket() async throws {
        let transport = URLSessionRangeTransport()
        let url = server.url("/trickle")
        let received = Locked(0)
        let read = Task { () -> Int in
            let response = try await transport.fetch(url, range: range)
            for try await chunk in response.body { received.withLock { $0 += chunk.count } }
            // A cancelled stream may simply end; the engine checks the same way after its loop.
            try Task.checkCancellation()
            return received.current
        }
        let started = await eventually { received.current >= 4_096 }
        XCTAssertTrue(started)
        let cancelledAt = Date()
        read.cancel()
        do {
            _ = try await read.value
            XCTFail("a cancelled read finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
        let closed = await eventually { self.server.closes("/trickle") == 1 }
        XCTAssertTrue(closed)
    }

    func testDroppingTheBodyCancelsTheRequest() async throws {
        let transport = URLSessionRangeTransport()
        do {
            let response = try await transport.fetch(server.url("/trickle"), range: range)
            XCTAssertEqual(response.status, 206)
        }
        let closed = await eventually { self.server.closes("/trickle") == 1 }
        XCTAssertTrue(closed)
    }
}

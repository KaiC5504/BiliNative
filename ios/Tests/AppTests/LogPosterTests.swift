#if DEV_TOOLS
import XCTest
import Network
@testable import BiliNative

final class LogPosterTests: XCTestCase {
    /// A local TCP server that answers each request's first chunk with `reply`, or never answers when it is nil.
    private func startListener(reply: String?) async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                guard let reply else { return }
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        return listener
    }

    func testOKAnswerSucceeds() async throws {
        let listener = try await startListener(reply: "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        defer { listener.cancel() }
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: listener.port!.rawValue))
        try await poster.post(Data("{}\n".utf8))
    }

    func testNon200AnswerIsAnError() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: server.port!))
        do {
            try await poster.post(Data("{}\n".utf8))
            XCTFail("expected an error for a 405 answer")
        } catch LogPoster.Failure.status(let line) {
            XCTAssertTrue(line.contains("405"))
        }
    }

    func testUnreachableTargetFailsFast() async {
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: 9))
        let started = Date()
        do {
            try await poster.post(Data("{}\n".utf8))
            XCTFail("expected an error")
        } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testSilentPeerHitsTheDeadline() async throws {
        let listener = try await startListener(reply: nil)
        defer { listener.cancel() }
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: listener.port!.rawValue), deadline: 1)
        let started = Date()
        do {
            try await poster.post(Data("{}\n".utf8))
            XCTFail("expected a timeout")
        } catch LogPoster.Failure.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testCancellationEndsAStalledPost() async throws {
        let listener = try await startListener(reply: nil)
        defer { listener.cancel() }
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: listener.port!.rawValue), deadline: 30)
        let started = Date()
        let task = Task { try await poster.post(Data("{}\n".utf8)) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    @MainActor
    func testManualAddressIsTrimmed() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "log-target-\(UUID().uuidString)")!)
        settings.logServerManual = " 192.168.1.5:47321\n"
        XCTAssertEqual(LogTarget(settings: settings), .manual(host: "192.168.1.5", port: 47321))
        settings.logServerManual = "192.168.1.5"
        XCTAssertNil(LogTarget(settings: settings))
    }
}
#endif

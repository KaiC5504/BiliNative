#if DEV_TOOLS
import XCTest
@testable import BiliNative

final class LogPosterTests: XCTestCase {
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
}
#endif

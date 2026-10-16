import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class HistoryModelTests: XCTestCase {
    private typealias F = HomeFixtures
    private let historyPath = "/x/web-interface/history/cursor"

    func testHistoryPagesUntilEmpty() async throws {
        let http = FixtureHTTP()
        let model = HistoryModel(client: BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T"])))

        await model.loadMore()
        XCTAssertEqual(model.items.count, F.historyPageSizes[0])
        XCTAssertFalse(model.isEnd)
        await model.loadMore()
        XCTAssertEqual(model.items.count, F.historyPageSizes.reduce(0, +))
        XCTAssertFalse(model.isEnd)
        await model.loadMore()
        XCTAssertTrue(model.isEnd)
        XCTAssertEqual(model.items.count, F.historyPageSizes.reduce(0, +))

        await model.loadMore()
        let sent = http.requests(to: historyPath)
        XCTAssertEqual(sent.count, 3, "nothing is asked once a page came back empty")
        let second = try XCTUnwrap(URLComponents(url: sent[1].url, resolvingAgainstBaseURL: false)?.queryItems)
        // The first page ends with the sixth fixture video, aid 810000005.
        XCTAssertEqual(second.first { $0.name == "max" }?.value, "810000005")
        XCTAssertEqual(model.sections.flatMap(\.items).map(\.id), model.items.map(\.id))
    }

    func testFinishedHistoryItemOpensAtTheStart() async throws {
        let model = HistoryModel(client: BiliClient(transport: FixtureHTTP(), cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T"])))
        await model.loadMore()

        let finished = try XCTUnwrap(model.items.first { $0.bvid == F.finishedBvid })
        XCTAssertEqual(finished.progress, -1)
        let route = HistoryModel.route(for: finished)
        XCTAssertEqual(route.bvid, F.finishedBvid)
        XCTAssertEqual(route.cid, finished.cid)
        XCTAssertEqual(route.startSeconds, 0)
        XCTAssertEqual(HistoryModel.progressLabel(for: finished), "已看完")

        let partway = try XCTUnwrap(model.items.first)
        XCTAssertEqual(HistoryModel.route(for: partway).startSeconds, Double(partway.progress))
        XCTAssertEqual(HistoryModel.progressLabel(for: partway), "00:02/02:12")
    }

    func testLoggedOutAnswerAsksForLogin() async {
        let model = HistoryModel(client: BiliClient(transport: LoggedOutHTTP(), cookies: CookieJar()))
        await model.loadMore()
        XCTAssertTrue(model.needsLogin)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.error)
    }

    /// Pull to refresh: the rows stay until the first page answers, then the list is that page alone.
    func testReloadKeepsTheRowsUntilTheFirstPageAnswers() async {
        let http = HoldingHTTP(path: historyPath)
        let model = HistoryModel(client: BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T"])))
        await model.loadMore()
        await model.loadMore()
        let all = F.historyPageSizes.reduce(0, +)
        XCTAssertEqual(model.items.count, all)

        http.hold()
        let reload = Task { await model.reload() }
        while http.requests(to: historyPath).count < 3 { await Task.yield() }
        XCTAssertEqual(model.items.count, all, "the list emptied before the answer")
        XCTAssertTrue(model.loading)
        http.release()
        await reload.value
        XCTAssertEqual(model.items.count, F.historyPageSizes[0])
        XCTAssertFalse(model.isEnd)
        XCTAssertFalse(model.loading)
        await model.loadMore()
        XCTAssertEqual(model.items.count, all, "the reload lost its place")
    }

    /// A reload while a page is still loading (a login landing during the first, cookie-less load) is not refused,
    /// and the older answer cannot append to the new list.
    func testReloadSupersedesALoadInFlight() async {
        let http = HoldingHTTP(path: historyPath)
        let model = HistoryModel(client: BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T"])))
        await model.loadMore()
        http.hold()
        let more = Task { await model.loadMore() }
        while http.requests(to: historyPath).count < 2 { await Task.yield() }
        let reload = Task { await model.reload() }
        while http.requests(to: historyPath).count < 3 { await Task.yield() }
        http.release()
        await more.value
        await reload.value
        XCTAssertEqual(model.items.count, F.historyPageSizes[0])
        XCTAssertEqual(Set(model.items.map(\.id)).count, model.items.count)
        XCTAssertFalse(model.loading)
    }

    func testTimeLabelShowsTheClockForTodayAndYesterdayAndTheDateBefore() {
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        // 2026-10-17 01:00 in UTC+8.
        let now = Date(timeIntervalSince1970: 1_792_170_000)
        XCTAssertEqual(HistoryModel.timeLabel(1_792_168_200, now: now, timeZone: zone), "00:30")
        XCTAssertEqual(HistoryModel.timeLabel(1_792_162_800, now: now, timeZone: zone), "23:00")
        XCTAssertEqual(HistoryModel.timeLabel(1_791_088_200, now: now, timeZone: zone), "2026年10月4日 12:30")
    }
}

/// Holds requests to one path while held; `release` lets every held one through.
final class HoldingHTTP: FixtureHTTP, @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var gate: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)?

    init(path: String) {
        self.path = path
        super.init()
    }

    func hold() {
        lock.withLock { gate = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded) }
    }

    func release() {
        lock.withLock {
            gate?.continuation.finish()
            gate = nil
        }
    }

    override func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let held = request.url.path == path ? lock.withLock { gate?.stream } : nil
        let response = try await super.send(request)
        if let held {
            for await _ in held {}
        }
        return response
    }
}

private final class LoggedOutHTTP: FixtureHTTP, @unchecked Sendable {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path == "/x/web-interface/history/cursor" else { return super.answer(request) }
        return (200, Data(#"{"code":-101,"message":"账号未登录","ttl":1}"#.utf8))
    }
}

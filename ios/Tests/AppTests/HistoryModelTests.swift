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

    func testTimeLabelShowsTheClockForTodayAndYesterdayAndTheDateBefore() {
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        // 2026-10-17 01:00 in UTC+8.
        let now = Date(timeIntervalSince1970: 1_792_170_000)
        XCTAssertEqual(HistoryModel.timeLabel(1_792_168_200, now: now, timeZone: zone), "00:30")
        XCTAssertEqual(HistoryModel.timeLabel(1_792_162_800, now: now, timeZone: zone), "23:00")
        XCTAssertEqual(HistoryModel.timeLabel(1_791_088_200, now: now, timeZone: zone), "2026年10月4日 12:30")
    }
}

private final class LoggedOutHTTP: FixtureHTTP, @unchecked Sendable {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path == "/x/web-interface/history/cursor" else { return super.answer(request) }
        return (200, Data(#"{"code":-101,"message":"账号未登录","ttl":1}"#.utf8))
    }
}

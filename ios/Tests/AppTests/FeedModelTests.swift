import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class FeedModelTests: XCTestCase {
    private typealias F = HomeFixtures
    private let feedPath = "/x/web-interface/wbi/index/top/feed/rcmd"

    func testRefreshReplacesAndLoadMoreAppendsWithoutDuplicates() async {
        let http = FixtureHTTP()
        let model = FeedModel(client: BiliClient(transport: http, cookies: CookieJar()))

        await model.refresh()
        let first = (0..<F.feedPageSize).map { F.feedBvid(page: 1, slot: $0) }
        XCTAssertEqual(model.cards.map(\.bvid), first, "ads and live cards are dropped")

        await model.loadMore()
        // Page 2 repeats page 1's last video; it stays where it first appeared.
        let second = (0..<F.feedPageSize).map { F.feedBvid(page: 2, slot: $0) }
        XCTAssertEqual(model.cards.map(\.bvid), first + second)
        XCTAssertEqual(Set(model.cards.map(\.bvid)).count, model.cards.count)

        await model.refresh()
        XCTAssertEqual(model.cards.map(\.bvid), first)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)

        let indices = http.requests(to: feedPath).map { request in
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "fresh_idx" }?.value
        }
        XCTAssertEqual(indices, ["1", "2", "1"])
    }

    func testFailedLoadMoreKeepsTheCardsAndRetriesTheSameIndex() async {
        let http = FailingFeedHTTP()
        let model = FeedModel(client: BiliClient(transport: http, cookies: CookieJar()))
        await model.refresh()
        http.failing = true
        await model.loadMore()
        XCTAssertEqual(model.cards.count, F.feedPageSize)
        XCTAssertNotNil(model.error)

        http.failing = false
        await model.loadMore()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.cards.count, F.feedPageSize * 2)
        let indices = http.requests(to: feedPath).compactMap { request in
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "fresh_idx" }?.value
        }
        XCTAssertEqual(indices, ["1", "2", "2"])
    }
}

private final class FailingFeedHTTP: FixtureHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private var _failing = false

    var failing: Bool {
        get { lock.withLock { _failing } }
        set { lock.withLock { _failing = newValue } }
    }

    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard failing, request.url.path.hasSuffix("/feed/rcmd") else { return super.answer(request) }
        return (500, Data())
    }
}

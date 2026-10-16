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

    /// A page that adds nothing new leaves no card to ask for the next one, so load more asks on by itself.
    func testAPageOfRepeatsGoesOnToTheNext() async {
        let http = RepeatingFeedHTTP()
        let model = FeedModel(client: BiliClient(transport: http, cookies: CookieJar()))
        await model.refresh()
        await model.loadMore()
        let first = (0..<F.feedPageSize).map { F.feedBvid(page: 1, slot: $0) }
        let third = (0..<F.feedPageSize).map { F.feedBvid(page: 3, slot: $0) }
        // Page 3 opens with page 2's last video, as every page repeats the one before it.
        XCTAssertEqual(model.cards.map(\.bvid), first + [F.feedBvid(page: 2, slot: F.feedPageSize - 1)] + third)
        XCTAssertEqual(indices(http), ["1", "2", "3"])
        await model.loadMore()
        XCTAssertEqual(indices(http).last, "4")
    }

    /// A load more that answers after a refresh must not append the old feed's next page to the new one.
    func testALoadMoreThatLandsAfterARefreshIsDropped() async {
        let http = HoldingHTTP(path: feedPath)
        let model = FeedModel(client: BiliClient(transport: http, cookies: CookieJar()))
        await model.refresh()
        http.hold()
        let more = Task { await model.loadMore() }
        while http.requests(to: feedPath).count < 2 { await Task.yield() }
        http.release()
        await model.refresh()
        await more.value
        let first = (0..<F.feedPageSize).map { F.feedBvid(page: 1, slot: $0) }
        XCTAssertEqual(model.cards.map(\.bvid), first)
        XCTAssertFalse(model.loading)
        await model.loadMore()
        XCTAssertEqual(indices(http).last, "2", "the refresh did not start the paging over")
    }

    private func indices(_ http: FixtureHTTP) -> [String?] {
        http.requests(to: feedPath).map { request in
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "fresh_idx" }?.value
        }
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

/// Answers page 2 with page 1 again: every card on it is already shown.
private final class RepeatingFeedHTTP: FixtureHTTP, @unchecked Sendable {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path.hasSuffix("/feed/rcmd"),
              var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "fresh_idx" })?.value == "2" else { return super.answer(request) }
        parts.queryItems = parts.queryItems?.map { $0.name == "fresh_idx" ? URLQueryItem(name: "fresh_idx", value: "1") : $0 }
        guard let url = parts.url else { return super.answer(request) }
        return DemoFixtures.response(for: url, method: request.method)
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

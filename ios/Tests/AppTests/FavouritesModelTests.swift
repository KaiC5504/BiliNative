import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class FavouritesModelTests: XCTestCase {
    /// 新建收藏夹 after the list failed, then 重试: the new folder stays in the list and ticked, so 完成 adds to it.
    func testAFolderMadeBeforeTheListLoadsKeepsItsTick() async throws {
        let http = FlakyFoldersHTTP()
        let client = BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let model = FavouritesModel(client: client, aid: VideoPageFixtures.aidA, mid: { 10001 })

        http.failing = true
        await model.load()
        XCTAssertEqual(model.phase, .failed)
        let made = await model.create(title: "新建的收藏夹", isPrivate: false)
        XCTAssertTrue(made)
        XCTAssertTrue(model.ticked.contains(3004))

        http.failing = false
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.folders.map(\.id), [3001, 3004, 3002, 3003])
        XCTAssertEqual(model.ticked, [3001, 3004])
        XCTAssertEqual(model.change.add, [3004])
        XCTAssertEqual(model.change.remove, [])
    }
}

private final class FlakyFoldersHTTP: FixtureHTTP, @unchecked Sendable {
    private let lock = NSLock()
    private var _failing = false

    var failing: Bool {
        get { lock.withLock { _failing } }
        set { lock.withLock { _failing = newValue } }
    }

    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard failing, request.url.path == "/x/v3/fav/folder/created/list-all" else { return super.answer(request) }
        return (500, Data())
    }
}

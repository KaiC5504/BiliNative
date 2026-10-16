import XCTest
@testable import BiliNative

@MainActor
final class RecentStoreTests: XCTestCase {
    func testNewestFirstWithoutDuplicatesAndCapped() {
        let defaults = makeDefaults()
        let store = RecentStore(defaults: defaults)
        for index in 0..<35 {
            store.add(PlayerRoute(bvid: "BV\(index)", cid: Int64(index), title: "t\(index)", part: "", page: 1, pageCount: 1))
        }
        store.add(PlayerRoute(bvid: "BV3", cid: 3, title: "t3", part: "", page: 1, pageCount: 1))
        XCTAssertEqual(store.items.count, 30)
        XCTAssertEqual(store.items.first?.bvid, "BV3")
        XCTAssertEqual(store.items.filter { $0.bvid == "BV3" }.count, 1)
        XCTAssertEqual(RecentStore(defaults: defaults).items.first?.bvid, "BV3")
    }

    func testClearEmptiesTheListAndWhatIsStored() {
        let defaults = makeDefaults()
        let store = RecentStore(defaults: defaults)
        store.add(PlayerRoute(bvid: "BV1", cid: 1, title: "t1", part: "", page: 1, pageCount: 1))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(RecentStore(defaults: defaults).items.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "recents-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}

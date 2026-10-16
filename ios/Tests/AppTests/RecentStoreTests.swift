import XCTest
@testable import BiliNative

@MainActor
final class RecentStoreTests: XCTestCase {
    func testNewestFirstWithoutDuplicatesAndCapped() {
        let defaults = UserDefaults(suiteName: "recents-\(UUID().uuidString)")!
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
}

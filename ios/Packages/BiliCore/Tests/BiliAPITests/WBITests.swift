import XCTest
@testable import BiliAPI

final class WBITests: XCTestCase {
    func testMD5Vectors() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("a"), "0cc175b9c0f1b6a831c399e269772661")
        XCTAssertEqual(MD5.hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hex("message digest"), "f96b697d7cb7938d525a2f31aaf161d0")
        XCTAssertEqual(MD5.hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 1000)).count, 32)
    }

    func testMixinKey() {
        XCTAssertEqual(WBI.mixinKey(imgKey: "7cd084941338484aae1ad9425b84077c", subKey: "4932caff0ff746eab6f01bf08b70ac45"),
                       "ea1db124af3c7062474693fa704f4ff8")
    }

    func testKeyFromURL() {
        XCTAssertEqual(WBI.key(fromURL: "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png"),
                       "7cd084941338484aae1ad9425b84077c")
    }

    func testSignedQueryReferenceVector() {
        let query = WBI.signedQuery(["foo": "114", "bar": "514", "zab": "1919810"],
                                    mixinKey: "ea1db124af3c7062474693fa704f4ff8", wts: 1_702_204_169)
        XCTAssertEqual(query, "bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4")
    }

    func testSignedQueryFiltersAndEncodes() {
        let query = WBI.signedQuery(["keyword": "中文 a+b!(x)"], mixinKey: "ea1db124af3c7062474693fa704f4ff8", wts: 1_700_000_000)
        XCTAssertEqual(query, "keyword=%E4%B8%AD%E6%96%87%20a%2Bbx&wts=1700000000&w_rid=391f961efc403664b08d417a32bbba8b")
    }
}

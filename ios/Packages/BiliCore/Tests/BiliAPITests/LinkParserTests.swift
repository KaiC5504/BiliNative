import XCTest
@testable import BiliAPI

final class LinkParserTests: XCTestCase {
    func testFullVideoURLWithPage() {
        XCTAssertEqual(LinkParser.parse("https://www.bilibili.com/video/BV1GJ411x7h7?p=2&spm_id_from=333.1007"),
                       .bvid("BV1GJ411x7h7", page: 2))
    }

    func testBareIDs() {
        XCTAssertEqual(LinkParser.parse("BV1GJ411x7h7"), .bvid("BV1GJ411x7h7", page: nil))
        XCTAssertEqual(LinkParser.parse("av170001"), .aid(170001, page: nil))
        XCTAssertEqual(LinkParser.parse("https://m.bilibili.com/video/av170001"), .aid(170001, page: nil))
    }

    func testTextSharedFromTheOfficialApp() {
        let shared = "【拥有NPC剧情、CG动画、GalGame的MC整合包『化龍』1.4正式版发布-哔哩哔哩】 https://b23.tv/xyZ123a 快来看看吧！"
        XCTAssertEqual(LinkParser.parse(shared), .short(URL(string: "https://b23.tv/xyZ123a")!))
        XCTAssertEqual(LinkParser.parse("看看这个 https://bili2233.cn/AbC9"), .short(URL(string: "https://bili2233.cn/AbC9")!))
        XCTAssertEqual(LinkParser.parse("  \nBV1GJ411x7h7\n "), .bvid("BV1GJ411x7h7", page: nil))
    }

    func testShareTextWithQueryAndFullWidthNeighbours() {
        let withQuery = "【标题】 https://b23.tv/AbCd123?share_source=copy 复制此链接，打开哔哩哔哩"
        XCTAssertEqual(LinkParser.parse(withQuery), .short(URL(string: "https://b23.tv/AbCd123")!))

        let touching = "【标题】https://b23.tv/AbCd123，快来看！"
        XCTAssertEqual(LinkParser.parse(touching), .short(URL(string: "https://b23.tv/AbCd123")!))

        let bracketed = "「看这个https://www.bilibili.com/video/BV1GJ411x7h7?p=3」"
        XCTAssertEqual(LinkParser.parse(bracketed), .bvid("BV1GJ411x7h7", page: 3))

        XCTAssertEqual(LinkParser.parse("推荐：av170001，不错"), .aid(170001, page: nil))
    }

    func testRejectsNonLinks() {
        XCTAssertNil(LinkParser.parse("hello"))
        XCTAssertNil(LinkParser.parse("BV1GJ411x7h"))
        XCTAssertNil(LinkParser.parse("travel tips"))
    }
}

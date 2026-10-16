import XCTest
@testable import AppLogic

final class QualityNamesTests: XCTestCase {
    func testFullNamesAreTheOfficialAppsNotTheServers() {
        XCTAssertEqual(QualityNames.full(qn: 125, serverText: "真彩 HDR"), "HDR 真彩")
        XCTAssertEqual(QualityNames.full(qn: 120, serverText: "超清 4K"), "4K 超高清")
        XCTAssertEqual(QualityNames.full(qn: 116, serverText: "高清 1080P60"), "1080P 60帧")
        XCTAssertEqual(QualityNames.full(qn: 80, serverText: "高清 1080P"), "1080P 高清")
        XCTAssertEqual(QualityNames.full(qn: 64, serverText: "高清 720P"), "720P 准高清")
        XCTAssertEqual(QualityNames.full(qn: 32, serverText: "清晰 480P"), "480P 标清")
    }

    func testFullFallsBackToTheServersTextThenTheNumber() {
        XCTAssertEqual(QualityNames.full(qn: 999, serverText: "未知"), "未知")
        XCTAssertEqual(QualityNames.full(qn: 999, serverText: nil), "999")
    }

    func testShortNamesForThePlayerButton() {
        XCTAssertEqual(QualityNames.short(qn: 120, serverText: "超清 4K"), "4K")
        XCTAssertEqual(QualityNames.short(qn: 32, serverText: nil), "480P")
        XCTAssertEqual(QualityNames.short(qn: 126, serverText: nil), "杜比视界")
    }

    func testShortFallsBackToTheLastWordOfTheServersTextThenAPlaceholder() {
        XCTAssertEqual(QualityNames.short(qn: 999, serverText: "高清 900P"), "900P")
        XCTAssertEqual(QualityNames.short(qn: 999, serverText: nil), "清晰度")
    }

    func testEveryFullNameHasAShortName() {
        for qn in [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16] {
            XCTAssertNotEqual(QualityNames.short(qn: qn, serverText: nil), "清晰度", "qn \(qn)")
            XCTAssertNotEqual(QualityNames.full(qn: qn, serverText: nil), String(qn), "qn \(qn)")
        }
    }
}

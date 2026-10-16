import XCTest
@testable import AppLogic

final class QualityRulesTests: XCTestCase {
    func testNeedsVipFrom112() {
        XCTAssertFalse(QualityRules.needsVip(80))
        XCTAssertFalse(QualityRules.needsVip(111))
        XCTAssertTrue(QualityRules.needsVip(112))
        XCTAssertTrue(QualityRules.needsVip(127))
    }

    func testAutoQualityRespectsVip() {
        XCTAssertEqual(QualityRules.auto(offered: [120, 116, 80, 64], isVip: false), 80)
        XCTAssertEqual(QualityRules.auto(offered: [120, 80], isVip: true), 120)
    }

    func testAutoQualityPicksHighestWhateverTheOrder() {
        XCTAssertEqual(QualityRules.auto(offered: [32, 80, 64, 116], isVip: false), 80)
        XCTAssertEqual(QualityRules.auto(offered: [32, 80, 64, 116], isVip: true), 116)
    }

    func testAutoQualityIsNilWhenNothingIsPlayable() {
        XCTAssertNil(QualityRules.auto(offered: [], isVip: true))
        XCTAssertNil(QualityRules.auto(offered: [120, 116], isVip: false))
    }
}

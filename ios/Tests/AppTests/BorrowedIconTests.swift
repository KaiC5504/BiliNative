import UIKit
import XCTest
@testable import BiliNative

final class BorrowedIconTests: XCTestCase {
    func testBorrowedFontAndArtLoad() {
        BorrowedIcon.registerFont()
        XCTAssertNotNil(UIFont(name: BorrowedIcon.fontName, size: 12))
        for icon in BorrowedIcon.allCases {
            XCTAssertNotNil(icon.glyphImage(), "\(icon) has no glyph in the font")
        }
        for name in ["ic_coins_one", "ic_coins_two", "ic_pay_coins_box", "ic_thunder_1"] {
            XCTAssertNotNil(BorrowedIcon.art(name), name)
        }
    }

    func testFallsBackWhenTheFontIsMissing() {
        for icon in BorrowedIcon.allCases {
            XCTAssertNil(icon.glyphImage(fontName: "no_such_font"))
            XCTAssertGreaterThan(icon.uiImage(fontName: "no_such_font").size.width, 0, "\(icon) has no fallback")
        }
    }
}

import XCTest
@testable import BiliNative

final class AppKeysTests: XCTestCase {
    // Compiling this proves the generated file is part of the app target; the pair itself is only present when
    // the BILI_APP_KEYS secret was set for the build.
    func testGeneratedKeysAreNilOrComplete() {
        if let tv = AppKeys.tv {
            XCTAssertFalse(tv.key.isEmpty)
            XCTAssertFalse(tv.secret.isEmpty)
        }
    }
}

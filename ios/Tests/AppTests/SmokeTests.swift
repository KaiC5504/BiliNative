import XCTest
@testable import BiliNative

final class SmokeTests: XCTestCase {
    func testVersionIsBuiltFromTheBundleKeys() {
        let range = AppInfo.version.range(of: #"^\d+\.\d+\.\d+ \(\d+\)$"#, options: .regularExpression)
        XCTAssertNotNil(range, "unexpected version string: \(AppInfo.version)")
    }

    func testDisplayNameComesFromTheInfoPlist() {
        let plistName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        XCTAssertNotNil(plistName)
        XCTAssertFalse(AppInfo.displayName.isEmpty)
        XCTAssertEqual(AppInfo.displayName, plistName)
    }

    func testDebugConfigurationCarriesBothCompilationConditions() {
        #if DEBUG && DEV_TOOLS
        #else
        XCTFail("Debug must compile with DEBUG and DEV_TOOLS")
        #endif
    }
}

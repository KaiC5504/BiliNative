import XCTest
import AppLogic
@testable import BiliNative

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsAndPersistence() {
        let defaults = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.nodeChoice, .overseas)
        XCTAssertTrue(settings.btrEnabled)
        XCTAssertEqual(settings.preferredCodec, .hevc)
        settings.nodeChoice = .mainland
        settings.btrEnabled = false
        settings.logServerManual = "192.168.1.5:47321"
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.nodeChoice, .mainland)
        XCTAssertFalse(reloaded.btrEnabled)
        XCTAssertEqual(reloaded.logServerManual, "192.168.1.5:47321")
    }

    func testPlayerSettingsDefaultsAndPersistence() {
        let defaults = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.autoplay)
        XCTAssertEqual(settings.loop, LoopMode.none)
        XCTAssertEqual(settings.fit, .fit)
        settings.autoplay = false
        settings.loop = .list
        settings.fit = .ratio4x3
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.autoplay)
        XCTAssertEqual(reloaded.loop, .list)
        XCTAssertEqual(reloaded.fit, .ratio4x3)
    }
}

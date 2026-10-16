import XCTest
@testable import BiliNative

final class CodecMemoryTests: XCTestCase {
    func testFailedKindsMoveToTheBackAndDolbyIsExcluded() {
        let memory = CodecMemory(defaults: UserDefaults(suiteName: "codec-\(UUID().uuidString)")!)
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["av1", "hevc", "avc"])
        memory.markFailed("av1")
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["hevc", "avc"])
        XCTAssertFalse(memory.excludesDolby)
        memory.markFailed("dolby")
        XCTAssertTrue(memory.excludesDolby)
        memory.reset()
        XCTAssertEqual(memory.order(preferred: .hevc).map(\.rawValue), ["hevc", "av1", "avc"])
    }
}

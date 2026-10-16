import XCTest
@testable import BiliNative

final class CodecMemoryTests: XCTestCase {
    func testFailedKindsMoveToTheBack() {
        let memory = CodecMemory(defaults: UserDefaults(suiteName: "codec-\(UUID().uuidString)")!)
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["av1", "hevc", "avc"])
        memory.markFailed("av1")
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["hevc", "avc"])
        memory.markFailed("dolby")
        XCTAssertEqual(memory.failedKinds, ["av1", "dolby"])
        memory.reset()
        XCTAssertEqual(memory.order(preferred: .hevc).map(\.rawValue), ["hevc", "av1", "avc"])
    }

    func testRemembersRealHEV1EntriesUntilReset() {
        let memory = CodecMemory(defaults: UserDefaults(suiteName: "codec-\(UUID().uuidString)")!)
        XCTAssertFalse(memory.hev1LabelsHoldHEV1)
        memory.noteHEV1Entry()
        XCTAssertTrue(memory.hev1LabelsHoldHEV1)
        memory.reset()
        XCTAssertFalse(memory.hev1LabelsHoldHEV1)
    }
}

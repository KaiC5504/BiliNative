import AVFoundation
import XCTest
@testable import BiliNative

final class PlaybackPolicyTests: XCTestCase {
    private let everyCodec = DebugSupport.codecDash([(80, 12, "hev1.1.6.L120.90"), (80, 13, "av01.0.08M.08"), (80, 7, "avc1.640032")])

    func testChoiceSkipsRejectedCodecs() {
        let first = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: [])
        XCTAssertEqual(first?.video.codecid, 12)
        let second = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc"])
        XCTAssertEqual(second?.video.codecid, 13)
        let third = PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc", "av1"])
        XCTAssertEqual(third?.video.codecid, 7)
    }

    func testChoiceNeverFallsBackToARejectedCodec() {
        // TrackSelector's any-codec fallback would hand back the rejected stream here.
        let hevcOnly = DebugSupport.codecDash([(80, 12, "hvc1.1.6.L120.90")])
        XCTAssertNil(PlaybackController.choose(hevcOnly, quality: 80, codecOrder: [.avc], excluded: ["hevc"]))
        XCTAssertNil(PlaybackController.choose(everyCodec, quality: 80, codecOrder: [.hevc, .av1, .avc], excluded: ["hevc", "av1", "avc"]))
    }

    func testUnknownCodecsAreOnlyTriedBeforeAnyRejection() {
        let unknown = DebugSupport.codecDash([(80, 99, "xyz1"), (64, 7, "avc1.640028")])
        XCTAssertEqual(PlaybackController.choose(unknown, quality: 80, codecOrder: [.hevc], excluded: [])?.video.codecid, 99)
        let afterRejection = PlaybackController.choose(unknown, quality: 80, codecOrder: [.avc], excluded: ["hevc"])
        XCTAssertEqual(afterRejection?.video.codecid, 7)
        XCTAssertEqual(afterRejection?.video.id, 64)
    }

    func testRejectedCodecMovesToALowerQualityThatHasAnother() {
        let dash = DebugSupport.codecDash([(120, 12, "hvc1.2.4.L153.90"), (80, 12, "hvc1.1.6.L120.90"), (80, 7, "avc1.640032")])
        let choice = PlaybackController.choose(dash, quality: 120, codecOrder: [.avc], excluded: ["hevc"])
        XCTAssertEqual(choice?.video.id, 80)
        XCTAssertEqual(choice?.video.codecid, 7)
    }

    func testDecoderErrorsAreFormatFailures() {
        let decode = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue)
        XCTAssertEqual(PlaybackController.classify(decode, log: []), .format)
        let parse = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue)
        XCTAssertEqual(PlaybackController.classify(parse, log: []), .format)
    }

    func testNetworkEvidenceWinsOverAFormatError() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(PlaybackController.classify(urlError, log: []), .network)
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue,
                              userInfo: [NSUnderlyingErrorKey: urlError])
        XCTAssertEqual(PlaybackController.classify(wrapped, log: []), .network)
        // An expired URL answers 403 with a body AVFoundation then fails to parse.
        let parse = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue)
        let refused = PlaybackController.ErrorLogEntry(domain: "CoreMediaErrorDomain", status: -12660, comment: "HTTP 403: Forbidden")
        XCTAssertEqual(PlaybackController.classify(parse, log: [refused]), .network)
        let status = PlaybackController.ErrorLogEntry(domain: "CoreMediaErrorDomain", status: 410, comment: "")
        XCTAssertEqual(PlaybackController.classify(parse, log: [status]), .network)
    }

    func testOtherErrorsAreUnknown() {
        XCTAssertEqual(PlaybackController.classify(NSError(domain: "CoreMediaErrorDomain", code: -12345), log: []), .unknown)
        XCTAssertEqual(PlaybackController.classify(nil, log: []), .unknown)
    }
}
